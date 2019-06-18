#!/bin/ksh93

# custom nagios plugin script to check local filesystems individually
# eddiegood@gmail.com

# 10/02/13: fixed os detection bug on solaris and added inode checking on solaris. EG
# Feb 2014: Adding pnp4nagios support to graph individual filesystems

#declarations
CRIT_STRING=""
WARN_STRING=""
EGREP_CMD="|egrep "
FS_LIST=""
export WARN_COUNT=0
export CRIT_COUNT=0
INCLUSIONS=""
EXCLUSIONS=""
LOCAL=""
LOCKFILE="/var/tmp/check_filesystems.lock"
OS=$(uname -s)

usage()
{
    echo
    echo "$0 [-hl] -w WARN% -c CRIT% [-t #seconds] [-f /filesystem1,/filesystem2,...] [-x exclusionfile_regex.txt | -i inclusionfile_regex.txt]"
    echo
    echo "    -c critical threshold for percent used"
    echo "    -w warning threshold for percent used"
    echo "    -l Local filesystems only (adds df -l which only works on Linux)"
    echo "    -f specific filesystem(s) to check, comma separated (if omitted, check all filesystems)"
    echo "    -x file containing regex list of exclusions (default is /etc/nagios/check_disk_exclusions.txt)"
    echo "         (-x also works with -f, but -x takes prescedence over -f)"
    echo "    -i file containing regex list of inclusions (overrides exclusions)";
    echo "    -h print this usage list."
    echo
    exit 4;
}

print_perfdata()
{


   printf "|";
   #printf ${perfdata[@]}
   for i in ${!perfdata[*]}; do
      printf "${i}=${perfdata["$i"]}\%;$WARN_THRESHOLD;$CRIT_THRESHOLD ";
   done

}

while getopts "hlc:w:x:f:i:" o
  do
    case $o in
       h)
          usage
          ;;
       w)
          WARN_THRESHOLD=$(printf $OPTARG|tr -d '%')
          ;;
       c)
          CRIT_THRESHOLD=$(printf $OPTARG|tr -d '%')
          ;;
       f)
          FS_LIST=$(printf $OPTARG | tr ',' ' ');
          ;;
       l)
          LOCAL=1
          ;;
       x) if [[ -e $OPTARG ]]; then
            EXCLUSIONS=$OPTARG
            EGREP_CMD="$EGREP_CMD -v -f $EXCLUSIONS"
          else
            echo "The specified exclusions file: $OPTARG doesn't exist."
            exit 3;
         fi
         ;;
       i) if [[ -e $OPTARG ]]; then
            INCLUSIONS=$OPTARG
            EGREP_CMD="$EGREP_CMD -f $EXCLUSIONS"
          else
            echo "The specified inclusions file: $OPTARG doesn't exist."
            exit 3;
         fi

         ;;
      \?)
          echo "Invalid option: -$OPTARG" >&2
          exit 4
          ;;
   esac
done

if [[ -z "$WARN_THRESHOLD" || -z "$CRIT_THRESHOLD" ]]; then
     echo "Error: Warning (-w) and Critical (-c) values are required."
     usage
fi

# some checks
if [[ $WARN_THRESHOLD -ge $CRIT_THRESHOLD ]];  then
     echo "Error: The warning threshold can't be higher than the critical threshold."
     usage
fi

if [[ -n "$INCLUSIONS"  &&  -n "$EXCLUSIONS" ]]; then
     echo "Error: The inclusions and exclusions options are mutually exclusive."
     usage
fi

#if Exclusions isn't set, use the default file, if it doesn't exist, don't exclude anything
if [[ -z "$EXCLUSIONS"  && -z "$INCLUSIONS" ]]; then
   if [[ -e "/etc/nagios/check_disk_exclusions.txt" ]]; then
      EGREP_CMD="| egrep -v -f /etc/nagios/check_disk_exclusions.txt"
   else
      EGREP_CMD=""
   fi
fi

if [ -f $LOCKFILE ]; then
   echo "WARNING: Previous check has hung (possibly due to a disconnected NFS mount)."
   exit 1;
fi


# create the lockfile
touch $LOCKFILE


# determine which OS we're working with
case $OS in

        aix|AIX)
                       export DF_CMD="df -Pg $FS_LIST"
                       export INODE_CMD="df $FS_LIST"
                       ;;
        Linux|linux)

                       if [[ -n $LOCAL ]]; then
                          export DF_CMD="df -Plh $FS_LIST"
                          export INODE_CMD="df -Pli $FS_LIST"
                       else
                          export DF_CMD="df -Ph $FS_LIST"
                          export INODE_CMD="df -Pi $FS_LIST"
                       fi
                       ;;
        solaris|SunOS)
                       export DF_CMD="df -k $FS_LIST"
                       export INODE_CMD="df -oi $FS_LIST"
                       ;;
        *)
                       echo "$0 doesn\'t support $OS. (sorry)";
                       exit 3;
esac


          #debug
          #echo WARN is $WARN_THRESHOLD
          #echo CRIT is $CRIT_THRESHOLD
          #echo "DF_CMD is ${DF_CMD} ${EGREP_CMD}"
# define the associative array for the perfdata
typeset -A perfdata

# jwalle01 - 20160216 - adding pre-check which checks stderr for the word error, to combat NFS issues which were triggering IO errors.
$DF_CMD 2>&1 >/dev/null | grep -i "error"
RETVAL=$?
if [ $RETVAL -eq 0 ]; then
  #the word error is being found in standard error output indicating a possible io error so alert as such.
  printf "CRITICAL: Possible I/O error in DF output. Please check."
  echo
  exit 2
fi

# AIX has different fields so it needs to be parsed seperately..
####### AIX df ################
if [[ $OS = 'AIX' || $OS = 'aix' ]]
then
   eval $DF_CMD 2>/dev/null $EGREP_CMD | while read line;
        do
        set -A arr $line
        arr[4]=$(echo ${arr[4]} | sed s/'%'//g )
        if [[ ${arr[4]} -ge $CRIT_THRESHOLD ]]
                then
                CRIT_STRING="$CRIT_STRING ${arr[0]} (${arr[5]}) is ${arr[4]}\% full ;"
                CRIT_COUNT=`expr $CRIT_COUNT + 1`
                else
                if [[ ${arr[4]} -ge $WARN_THRESHOLD ]]
                then
                WARN_STRING="$WARN_STRING ${arr[0]} (${arr[5]}) is ${arr[4]}\% full ;"
                WARN_COUNT=`expr $WARN_COUNT + 1`
                fi
        fi
        perfdata["${arr[5]}"]=${arr[4]};

        done


   eval $INODE_CMD 2>/dev/null $EGREP_CMD | while read line;
        do

        set -A arr $line
        arr[5]=$(echo ${arr[5]} | tr -d '%' )
        if [[ ${arr[5]} -gt $CRIT_THRESHOLD ]]
        then
                CRIT_STRING="$CRIT_STRING ${arr[0]} (${arr[6]}) is using ${arr[5]}\% of available inodes ;"
                CRIT_COUNT=`expr $CRIT_COUNT + 1`;
        else
        if [[ ${arr[5]} -ge $WARN_THRESHOLD ]]
                then
                WARN_STRING="$WARN_STRING ${arr[0]} (${arr[6]}) is using ${arr[5]}\% of available inodes ;"
                WARN_COUNT=`expr $WARN_COUNT + 1`
        fi
        fi
        perfdata["${arr[6]}(inodes)"]=${arr[5]};

        done
else
######## Linux and Solaris df #############
   eval $DF_CMD 2>/dev/null $EGREP_CMD | while read line;
        do
        set -A arr $line
        arr[4]=$(echo ${arr[4]} | sed s/'%'//g )
        if [[ ${arr[4]} -ge $CRIT_THRESHOLD ]]
                then
                CRIT_STRING="$CRIT_STRING ${arr[0]} (${arr[5]}) is ${arr[4]}\% full ;"
                CRIT_COUNT=`expr $CRIT_COUNT + 1`
                else
                if [[ ${arr[4]} -ge $WARN_THRESHOLD ]]
                then
                WARN_STRING="$WARN_STRING ${arr[0]} (${arr[5]}) is ${arr[4]}\% full ;"
                WARN_COUNT=`expr $WARN_COUNT + 1`
                fi
        fi
        perfdata["${arr[5]}"]=${arr[4]};


        done

# Check Inode usage:
   eval $INODE_CMD 2>/dev/null $EGREP_CMD | while read line;
       do
       # check solaris inodes
       if [[ $OS = 'SunOS' || $OS = 'solaris' ]]
        then
           set -A arr $line
           arr[3]=$(echo ${arr[3]} | tr -d '%' )
           perfdata["${arr[4]}(inodes)"]=${arr[3]};
           if [[ ${arr[3]} -gt $CRIT_THRESHOLD ]]
           then
                   CRIT_STRING="$CRIT_STRING ${arr[0]} (${arr[4]}) is using ${arr[3]}\% of available inodes ;"
                   CRIT_COUNT=`expr $CRIT_COUNT + 1`;
           else
           if [[ ${arr[3]} -ge $WARN_THRESHOLD ]]
                   then
                   WARN_STRING="$WARN_STRING ${arr[0]} (${arr[4]}) is using ${arr[3]}\% of available inodes ;"
                   WARN_COUNT=`expr $WARN_COUNT + 1`
           fi
           fi
        # linux inode usage
        else
           set -A arr $line
           arr[4]=$(echo ${arr[4]} | tr -d '%' )
           perfdata["${arr[5]}(inodes)"]=${arr[4]};
           if [[ ${arr[4]} -gt $CRIT_THRESHOLD ]]
           then
                   CRIT_STRING="$CRIT_STRING ${arr[0]} (${arr[5]}) is using ${arr[4]}\% of available inodes ;"
                   CRIT_COUNT=`expr $CRIT_COUNT + 1`;
           else
           if [[ ${arr[4]} -ge $WARN_THRESHOLD ]]
                   then
                   WARN_STRING="$WARN_STRING ${arr[0]} (${arr[5]}) is using ${arr[4]}\% of available inodes ;"
                   WARN_COUNT=`expr $WARN_COUNT + 1`
           fi
           fi
        fi
        done

fi

# remove the lockfile
rm $LOCKFILE

if [[ $CRIT_COUNT -ge 1 ]]
  then
   printf "CRITICAL: $CRIT_STRING $WARN_STRING"
   print_perfdata
   echo
   exit 2;
else
        if [[ $WARN_COUNT -ge 1 ]]
        then
           printf "WARNING: $WARN_STRING"
           print_perfdata
           echo
           exit 1
        else
           printf "All Filesystems are OK."
           print_perfdata
           echo
           exit 0
        fi
fi
