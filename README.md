# nagios_filesystems
Custom Nagios plugin to check filesystem status

this script checks individual or groups of file systems on Linux, Solaris and AIX. It supports inclusion and exclusion lists. 

check_filesystems.sh [-hl] -w WARN% -c CRIT% [-t #seconds] [-f /filesystem1,/filesystem2,...] [-x exclusionfile_regex.txt | -i inclusionfile_regex.txt]

    -c critical threshold for percent used
    -w warning threshold for percent used
    -l Local filesystems only (adds df -l which only works on Linux)
    -f specific filesystem(s) to check, comma separated (if omitted, check all filesystems)
    -x file containing regex list of exclusions (default is /etc/nagios/check_disk_exclusions.txt)
         (-x also works with -f, but -x takes prescedence over -f)
    -i file containing regex list of inclusions (overrides exclusions)
    -h print this usage list.

