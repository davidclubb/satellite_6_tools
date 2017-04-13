#!/bin/bash

# Deprecated - use puppet
exit

# Incept 20141211
# Author SDW
# Configure a RHEL or OEL system for Active Directory Authentication

if [[ $EUID != 0 ]]; then
   echo "FAILURE: This script must be run as root or with equivalent privilege."
   echo "         Setup has not been completed on this system."
   exit 2
fi


TS=`date +%Y%m%d%H%M%S`

### CONFIGURATION VARIABLES

# The DC list is a list of domain controllers the LDAP client will
# attempt to contact, in order
DCLIST="
knedcxiwp004.acmeplaza.com
knedcxiwp005.acmeplaza.com
knedcxiwp003.acmeplaza.com
"

# The Active Directory domain against which we'll be authenticating
ADDOMAIN=acmeplaza.com

# Bind user details
BINDDN='cn=linux.auth,ou=special accounts,ou=pks,ou=plaza,dc=acmeplaza,dc=com'
BINDPW='secret'


### OS VERSION 
echo "Checking OS version..."
unset ELV
if [[ -n `uname -r | grep -i el6` ]] || [[ -s /etc/nslcd.conf ]]; then
   echo "   Setting version to RHEL or OEL 6"
   ELV=6
elif [[ -n `uname -r | grep -i el5` ]]; then
   echo "   Setting version to RHEL or OEL 5"
   ELV=5
fi

### PACKAGE MANAGEMENT

# Check for required packages

case $ELV in

   5 ) REQPACKAGES="nmap bind-utils authconfig nss_ldap openldap openldap-clients cyrus-sasl-gssapi krb5-libs pam_krb5 krb5-workstation"
       ;;
   6 ) REQPACKAGES="nmap bind-utils authconfig nss-pam-ldapd openldap openldap-clients pam_ldap krb5-libs pam_krb5 krb5-workstation"
       ;;
   * ) echo "   Unsupported Operating System"
       exit
       ;;
esac

PACKAGECHECK=FAIL
while [[ "$PACKAGECHECK" != "PASS" ]]; do

   echo "Checking for required packages..."
   unset MISSINGPLIST
   for RP in $REQPACKAGES; do
      echo -n "   $RP is..."
      if [[ -z `/bin/rpm -qa $RP` ]]; then
         echo "missing"
         MISSINGPLIST="$MISSINGPLIST $RP"
      else
         echo "installed"
      fi
   done
   
   if [[ -n $MISSINGPLIST ]]; then
      unset CHOICEA
      echo "Attempt to install missing packages with YUM?"
      read -p "(Enter 'Y' to install, anything else to quit): " CHOICEA
      if [[ -z `echo $CHOICEA | grep -i "^Y"` ]]; then
         exit 1
      else
         echo "Running: /usr/bin/yum --nogpgcheck -y install $MISSINGPLIST"
         #/usr/bin/yum --nogpgcheck -q -y install $MISSINGPLIST
         /usr/bin/yum --nogpgcheck -y install $MISSINGPLIST
         YUMRESULT=$?
         if [[ $YUMRESULT -ne 0 ]]; then
            echo ""
            echo "YUM installation failed, please manually install the"
            echo "missing packages and re-run this script."
            exit 2
         fi
      fi
      
   else
      PACKAGECHECK=PASS
   fi
done


# Remove SSSD packages if necessary
if [[ $ELV -ge 6 ]] && [[ -n `/bin/rpm -qa | /bin/egrep 'sssd|ipa-client'` ]]; then
   echo "Removing IPA/SSSD packages"
   for p in `/bin/rpm -qa | /bin/egrep 'sssd|ipa-client'`;do
      REMOVELIST="$REMOVELIST $p"
   done
   /usr/bin/yum -q -y erase $REMOVELIST
fi

### CONFIGURATION

echo "Generating Configuraton Plan"

# backing up /etc/hosts
/bin/cp -rp /etc/hosts /etc/hosts.${TS}

# Validate DCs in DCLIST and create URISTRING from DCLIST
unset URISTRING
for DC in $DCLIST; do
   unset DCIP

   #Bypass the hosts file when looking up the IP in case it has changed
   DCIP=`/usr/bin/dig +short $DC`

   if [[ -z $DCIP ]]; then
      echo "   ERROR: unable to resolve the IP for [${DC}]"
      
   else
      # Make sure the servers are reachable on the needed ports
      PORTCHECK=PASS
      if [[ -z `nmap -P0 $DCIP -p 389 2>&1 | grep open | grep 389` ]]; then
         PORTCHECK=FAIL
         echo "   ERROR: unable to connect to [${DC}] on LDAP port (389) at $DCIP"
      fi
      if [[ -z `nmap -P0 $DCIP -p 636 2>&1 | grep open | grep 636` ]]; then
         PORTCHECK=FAIL
         echo "   ERROR: unable to connect to [${DC}] on LDAPS port (636) at $DCIP"
      fi

      # Add the DCs to the hosts file so Auth can tolerate DNS outages
      if [[ $PORTCHECK == PASS ]]; then

         # If the DC isn't already defined, then add it
         if [[ -z `/bin/grep -v "^#" /etc/hosts | /bin/grep -i "$DC"` ]]; then
            getent hosts $DC >> /etc/hosts
         else
            # If the DC is already defined, make sure it's right - otherwise fix it
            if [[ -z `/bin/grep -v "^#" /etc/hosts | /bin/grep -i "$DC" | /bin/grep "$DCIP"` ]]; then
               DCFIH=`/bin/grep -v "^#" /etc/hosts | /bin/grep -i "$DC" | awk '{print $2}'`
               /bin/sed -i "/$DCFIH/s/^/#/g" /etc/hosts
               getent hosts $DC >> /etc/hosts
            fi
         fi
        
         # If the DC passed the lookup and port tests then add it to the URI 
         if [[ -z $URISTRING ]]; then
            URISTRING="ldap://${DC}"
         else
            URISTRING="${URISTRING} ldap://${DC}"
         fi
      fi
   fi

done

if [[ -z $URISTRING ]]; then
   echo "FAILURE: No suitable domain controllers could be found"
   echo "   in the list.  Please update the list found in this"
   echo "   script or address the errors listed above and run "
   echo "   this script again."
   exit 3
else
   echo "   URI set to...$URISTRING"
fi

# Set the base DN based on the domain name
echo -n "   Base DN set to..."
unset BASEDN
for dc in `echo $ADDOMAIN | tr '[:upper:]' '[:lower:]' | sed 's/\./ /g'`; do
   if [[ -z $BASEDN ]]; then
      BASEDN="dc=${dc}"
   else
      BASEDN="${BASEDN},dc=${dc}"
   fi      
done
echo $BASEDN

# Set the kerberos realm based on the domain name
KRBREALM=`echo $ADDOMAIN | tr '[:lower:]' '[:upper:]'`
echo "   Kerberos realm set to...$KRBREALM"

# Write out the SSL CA Cert

echo "Writing SSL CA certificate for $ADDOMAIN"

mkdir -p /etc/openldap/cacerts

cat << EOF >> /etc/openldap/cacerts/${ADDOMAIN}.cacert.cer

subject=/DC=com/DC=ACMEPLAZA/CN=ACMEPLAZA-KHONEPLZDCX02-CA
issuer=/DC=com/DC=ACMEPLAZA/CN=ACMEPLAZA-KHONEPLZDCX02-CA
-----BEGIN CERTIFICATE-----
MIIDyTCCArGgAwIBAgIQSS7KRY8+6LpBCypo/4O0DDANBgkqhkiG9w0BAQUFADBZ
MRMwEQYKCZImiZPyLGQBGRYDY29tMRswGQYKCZImiZPyLGQBGRYLS0lFV0lUUExB
WkExJTAjBgNVBAMTHEtJRVdJVFBMQVpBLUtIT05FUExaRENYMDItQ0EwHhcNMTEw
OTA5MTM0NjA1WhcNMTYxMDEyMTEyMjUyWjBZMRMwEQYKCZImiZPyLGQBGRYDY29t
MRswGQYKCZImiZPyLGQBGRYLS0lFV0lUUExBWkExJTAjBgNVBAMTHEtJRVdJVFBM
QVpBLUtIT05FUExaRENYMDItQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
AoIBAQCehuyR6rPYiXY1bMGFoRlqlK5KYelKUM3Aj93rDB1oU6/CnfVzsPGny56g
9IhJFhdUTUH9Y+VeqFjfiUJ59KMMWjE7tY9m6JYz6k8UPaalzKI6ptlxQtrDouvy
JRdDFOF+g8KuHuKkpIItyKBiRKhT86uhlJ+iIPxozsnosHG6cycoM6rKBnZPs0P7
v2sj0dUX4x9Z+IAockBYbCKGNI8uZA84HEwXzNS1IrXxwcZp/ZPelNikqZ88f+pd
mr9boTzx8Nvvpnpii2rw66tsXhrVB3Cd35t0+XdS8bucLpypxBRPmXVSLy5xcjin
J3K/a4B7lyNDZ5y9DUIUpT/YKqsxAgMBAAGjgYwwgYkwEwYJKwYBBAGCNxQCBAYe
BABDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFBDy
kSe5laEOtDvdyGxy9a1GZM0nMBAGCSsGAQQBgjcVAQQDAgEBMCMGCSsGAQQBgjcV
AgQWBBRcQi3fwvix/7nvi+2cs6sEqZO9xDANBgkqhkiG9w0BAQUFAAOCAQEAZ7ZW
b/6y019BV8BBM6giYb2kZUdEn3eha/OpMELPe7gMk7O+19IBBOrc5kpplIqnY/WF
yJGAczkvCTXCiwTZ8q1Vcem6X4V55c4hvgSapjg4pb2kMDTICI2JuFUrXJq12t4V
Z/u7a1vq4ePL06TnWwFucBl1lewPLcFnBOSW9Oe3Ko3mmsaaIz8HIxTBJkHYGpH+
8Mq7Jn4WciJnH4qznetqygHvJwR1fxhD6J8BKrHwnBza71hJGDPVC+EMd0pkqjxO
H5s5G3VZpTgceDrnxOKV8eNbfDwt+YTJs+eyvIaqkBKC744duRL9MT0X2Y0ZludO
DIgwvehLAOO4+rw0bQ==
-----END CERTIFICATE-----

EOF

# Archive kerberos settings so they don't interfere with auth
if [[ -s /etc/krb5.conf ]]; then
   echo "Archiving current Kerberos settings"
   /bin/mv /etc/krb5.conf /etc/krb5.conf.${TS}
fi

# If winbind is running it needs to be shut down and disabled
if [[ -n `ps --no-header -C winbindd -o pid` ]]; then
   echo "Winbind detected - shutting it down and disabling - recommend uninstall"
   /sbin/chkconfig winbind off
   /etc/init.d/winbind stop
fi


# Remaining settings are version specific

if [[ $ELV -ge 6 ]]; then

   echo "Applying initial configuration for EL6"
   /usr/sbin/authconfig --enableshadow --enableldap --enableldapauth --ldapserver="$URISTRING" --ldapbasedn="$BASEDN" --enablekrb5 --krb5realm=$KRBREALM --enablekrb5kdcdns --enableforcelegacy --disablesssd --disablesssdauth --enablepamaccess --enablemkhomedir --disablewinbind --disablewinbindauth --updateall 

   echo "Applying secondary configuration for EL6"

   echo "   Enabling AD attribute mapping, setting idle timeout, adding bind user "

   # Remove any existing settings from the config file   
   sed -i.${TS} '/^pagesize/d;/^referrals/d;/^filter/d;/^map/d;/idle_timelimit /d;/^binddn/d;/^bindpw/d' /etc/nslcd.conf
  
   # Write new settings 
cat << EOF >> /etc/nslcd.conf
# Settings for Active Directory
pagesize 1000
referrals off
filter passwd (&(objectClass=user)(!(objectClass=computer))(uidNumber=*)(unixHomeDirectory=*))
map    passwd uid              sAMAccountName
map    passwd homeDirectory    unixHomeDirectory
map    passwd gecos            description
filter shadow (&(objectClass=user)(!(objectClass=computer))(uidNumber=*)(unixHomeDirectory=*))
map    shadow uid              sAMAccountName
map    shadow shadowLastChange pwdLastSet
filter group  (&(objectClass=group)(gidNumber=*))
map    group  uniqueMember     member

# Idle Session Timeout (in minutes)
idle_timelimit 10

# Bind user credentials
binddn $BINDDN
bindpw $BINDPW
EOF

   # Check for extraneous settings in pam_ldap.conf and remove them - needed for S24 conversions particularly
   if [[ -n `egrep '^tls_checkpeer|^pam_groupdn|^pam_member_attribute|^binddn|^bindpw' /etc/pam_ldap.conf` ]]; then
      echo "   Removing unneeded settings from /etc/pam_ldap.conf"
      sed -i.${TS} '/^tls_checkpeer/d;/^pam_groupdn/d;/^pam_member_attribute/d;/^binddn/d;/^bindpw/d' /etc/pam_ldap.conf
   fi
  
   # This is done in case authconfig decided not to remove them  
   if [[ -n `egrep 'pam_sss|pam_winbind' /etc/pam.d/*` ]]; then
      echo "   Removing erroneus entries from PAM"
      /bin/cp -rp /etc/pam.d/ /etc/pam.d.backup.{$TS}
      sed -i '/pam_sss/d;/pam_winbind/d' /etc/pam.d/*
   fi

   # Configure SSL
   echo "Configuring for SSL"

   echo "   Rehashing CA Cert"
   /usr/sbin/cacertdir_rehash /etc/openldap/cacerts

   echo "   Turning on SSL in LDAP"
   sed -i '/^ssl/d' /etc/nslcd.conf
   sed -i '/^ssl/d' /etc/pam_ldap.conf
   echo "ssl yes" >> /etc/nslcd.conf
   echo "ssl yes" >> /etc/pam_ldap.conf

   echo "   Updating URIs in LDAP"
   sed -i '/^uri/s/ldap:/ldaps:/g' /etc/nslcd.conf 
   sed -i '/^URI/s/ldap:/ldaps:/g' /etc/openldap/ldap.conf 
   sed -i '/^uri/s/ldap:/ldaps:/g' /etc/pam_ldap.conf

   echo "   Restarting daemons"
   /etc/init.d/nslcd restart
   /etc/init.d/nscd reload

else

   # Set up for RHEL 5
   echo "Applying initial configuration for EL5"
   /usr/sbin/authconfig --enableshadow --enableldap --enableldapauth --ldapserver="$URISTRING" --ldapbasedn="$BASEDN" --enablekrb5 --krb5realm=$KRBREALM --enablekrb5kdcdns --disablesssd --disablesssdauth --enablepamaccess --enablemkhomedir --disablewinbind --disablewinbindauth --updateall
   
   echo "Applying secondary configuration for EL5"

   # This is done in case authconfig decided not to remove them
   if [[ -n `egrep 'pam_sss|pam_winbind' /etc/pam.d/*` ]]; then
      echo "   Removing erroneus entries from PAM"
      /bin/cp -rp /etc/pam.d/ /etc/pam.d.backup.{$TS}
      sed -i '/pam_sss/d;/pam_winbind/d' /etc/pam.d/*
   fi


   echo "   Enabling AD attribute mapping, setting time limits, adding bind user "
  
   # Remove existing settings from the config file 
   sed -i.${TS} '/^nss_map_/d;/^nss_base_/d;/^pam_/d;/^timelimit /d;/^bind_timelimit/d;/^idle_timelimit /d;/^bind_policy /d;' /etc/ldap.conf

   # Write new settings
cat << TAG >> /etc/ldap.conf

## Settings for Active Directory
nss_map_objectclass posixAccount user
nss_map_objectclass shadowAccount user
nss_map_attribute uid sAMAccountName
nss_map_attribute homeDirectory unixHomeDirectory
nss_map_attribute shadowLastChange pwdLastSet
nss_map_objectclass posixGroup group
nss_map_attribute uniqueMember member
nss_map_attribute gecos description
pam_login_attribute sAMAccountName
pam_filter objectclass=User
pam_password ad

# Filters to ignore non-POSIX users and groups
nss_base_group ${BASEDN}?sub?gidNumber=*
nss_base_passwd ${BASEDN}?sub?uidNumber=*

# Time limits
timelimit 10
bind_timelimit 10
idle_timelimit 5

# Bind user credentials 
binddn $BINDDN
bindpw $BINDPW

# Bind policy
bind_policy soft

TAG

   # Configure SSL
   echo "Configuring for SSL"

   echo "   Rehashing CA Cert"
   /usr/sbin/cacertdir_rehash /etc/openldap/cacerts

   echo "   Turning on SSL in LDAP"
   sed -i '/^ssl/d' /etc/ldap.conf
   echo "ssl yes" >> /etc/ldap.conf

   echo "   Updating URIs in LDAP"
   sed -i '/^uri/s/ldap:/ldaps:/g' /etc/ldap.conf
   sed -i '/^URI/s/ldap:/ldaps:/g' /etc/openldap/ldap.conf

fi

### Configure Access.conf
echo "Configuring PAM Access Control"

sed -i.${TS} '/^[ +-]/d' /etc/security/access.conf

cat << EOF >> /etc/security/access.conf
+ : root unixpa unixaa LinuxLoginUsers: ALL
+ : ALL : cron crond at atd
- : ALL : ALL

EOF

echo "Configuration of LDAP for AD is completed, please test logins."



exit



