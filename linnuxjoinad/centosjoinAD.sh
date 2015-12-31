#!/bin/bash
#Please contact xlei.boll@gmail.com if any problems
workgroup=""
servername=""
domainname=""
dns=""
username=""

########################################################################
#Functions                                                             #
########################################################################
function Usage()
{
cat <<EOF
--------------------------------------------------------------
Usage: ${0##*/} [Options]

Options:
   -d|--dns          dns server IP
   -D|--domainname  domain name 
   -w|--workgroup    WORKGROUP.
   -S|--servername  <domain server name> Target Domain Server Name/Address
   -U|--username  <user name>     domain admin user name

Examples:
   ./centosjoinad.sh -d 192.168.0.1 -w DOMAIN -D domian.com -S adserver1.domain.com -U Administrator
   
Notes:
   1. Use domain admin administrator to register

--------------------------------------------------------------   
EOF
}

function InstallPreReq()
{
if [  distro=redhat ]; then
    echo "--> installing  samba-winbind krb5-workstation"
    sudo yum -y install nscd samba-winbind krb5-workstation
elif [distro=debian]; then
    echo "--> installing winbind samba smbfs smbclient libnss-winbind libpam-winbind"
    sudo apt-get install winbind samba smbfs smbclient libnss-winbind libpam-winbind
else
  distro=unknown
  echo The linux distribution is unkown. Will exit now.
  exit
fi
}


function ModifyHostName()
{
current_time=$(date "+%Y.%m.%d-%H.%M.%S")
echo "Backup the hosts file from /etc/hosts to /etc/hosts.$current_time"
cp /etc/hosts /etc/hosts.$current_time
HOSTNAME=$(hostname -s)
echo "Modify the new /etc/hosts to join domain"
sed -i "s/^127\.0\.0\.1.*$/127\.0\.0\.1  $HOSTNAME\.$domainname  $HOSTNAME/" /etc/hosts
echo "The hosts file after modification is:"
cat /etc/hosts
}

function ModifyDns()
{
current_time=$(date "+%Y.%m.%d-%H.%M.%S")
echo "Backup the hosts file from /etc/resolv.conf to /etc/resolv.conf.$current_time"
cp /etc/resolv.conf /etc/resolv.conf.$current_time
echo "Modify the new /etc/resolv.conf to join domain"
sed -i "s/^domain.*$/domain  $domainname/" /etc/resolv.conf
sed -i "s/^search.*$/search  $domainname/" /etc/resolv.conf
sed -i "s/^nameserver.*$/nameserver  $dns/" /etc/resolv.conf
echo "The /etc/resolv.conf  file after modification is:"
cat /etc/resolv.conf
}

function ModifySmbKrb()
{
mkdir /home/$workgroup
chmod 0777 /home/$workgroup
echo "run authconfig for create files for join the domain"
authconfig \
--update \
--kickstart \
--enablewinbind \
--enablewinbindauth \
--smbsecurity=ads \
--smbworkgroup=$workgroup \
--smbrealm=$domainname \
--smbservers=$servername \
--winbindjoin=$username \
--winbindtemplatehomedir=/home/%D/%U \
--winbindtemplateshell=/bin/bash \
--enablelocauthorize \
--enablemkhomedir

#modify the /etc/samba/smb.conf
sed -i 's/idmap\sconfig\s\*\s:\sbase_rid\s\=.*$/idmap\sconfig  \* : base_rid \=16777216/' /etc/samba/smb.conf
sed -i 's/idmap\sconfig\s\*\s:\srange\s\=.*$/idmap config  \* : range \=16777216\-33554431/' /etc/samba/smb.conf
sed -i 's/template\sshell\s\=\s\/bin\/bash.*$/template shell \= \/bin\/bash\n kerberos method \= secrets and keytab/' /etc/samba/smb.conf
#modify pam for winbind /etc/security/pam_winbind.conf
sed -i 's/;krb5_auth\s=.*$/krb5_auth \= yes/' /etc/security/pam_winbind.conf
sed -i 's/;krb5_ccache_type\s=.*$/krb5_ccache_type \= FILE/' /etc/security/pam_winbind.conf
sed -i 's/;mkhomedir\s=.*$/mkhomedir \= yes/' /etc/security/pam_winbind.conf
#restart winbind
service winbind restart
chkconfig winbind on
#restart nscd
service nscd start
chkconfig nscd on
}

function NetJoin()
{
#/usr/bin/net join -w WINCDK -S leoserver1.wincdk.qa -U Administrator
echo "disabled selinux..."
setenforce 0
echo "join domain with /usr/bin/net join ..."
/usr/bin/net join -w $workgroup  -S $serveranme -U $username
}

function VerifyJoin()
{
#net ads testjoin
echo "Verify the join by command :net ads testjoin"
net ads testjoin
}
function ConfirmOrExit()
{
while true
do
echo -n "Please confirm if you want to continue (y or n)"
read CONFIRM
case $CONFIRM in
y|Y|YES|yes|Yes) break ;;
n|N|no|NO|No)
echo "Aborting - you can also manual join linux to AD follow linux desktop qe wiki"
exit
;;
*) echo "Please enter only y or n"
esac
done
}
########################################################################
#Main                                                                  #
########################################################################

#Show usage
Usage

#======================================================================
#===Get Arguments
#======================================================================
while [ $# -ne 0 ]; do
   arg=$1
   shift
   case $arg in
   -d|--dns)
      dns="$1"
      shift
      ;;
   -D|--domainname)
      domainname="$1"
      shift
      ;;
   -w|--workgroup)
      workgroup="$1"
      shift
      ;;
   -S|--server)
      servername="$1"
      shift
      ;;
   -U|--user)
      username="$1"
      shift
      ;;
   *)
      echo "wrong cmdline options."
      exit 1
      ;;
   esac
done
if  [ -z $workgroup ]; then
echo workgroup is not specified.
exit
fi
if  [ -z $servername ]; then
echo servername is not specified.
exit
fi
if  [ -z $username ]; then
echo username is not specified.
exit
fi
#Determine the distribution
distro=unknown
rc_dir=/etc/rc.d
# Step 1: Determine the Distribution
if [ -f /etc/redhat-release ]; then
  # Also true for variants of Fedora or RHEL
  distro=redhat
elif [ -f /etc/debian_version ]; then
  # Also true for Ubuntu etc
  distro=debian
elif [ -f /etc/SuSE-brand ] || [ -f /etc/SuSE-release ]; then
  distro=suse
  echo suse are not supported now. Please wait for update...
  exit
elif [ -f /etc/slackware-version ]; then
  distro=slackware
  echo slackware are not supported now. Please wait for update...
  exit
else
  distro=unknown
  echo The linux distribution is unkown. Will exit now.
  exit
fi

InstallPreReq
ConfirmOrExit
ModifyHostName
ConfirmOrExit
ModifyDns
ConfirmOrExit
ModifySmbKrb
ConfirmOrExit
NetJoin
ConfirmOrExit
VerifyJoin
exit

