#!/bin/bash

IFS=$'\n'
set -e

filename=~/budget.txt
if [ ! -f $filename ]
then
	touch "$filename"
fi
year=`date +"%Y"`
month=''
quiet=false
calculate=false
while getopts ':ocm:y:q' opt; do
	case $opt in
		o)
			sed '/^$/d' $filename | sed '$d' >> tmp.txt
			mv tmp.txt $filename
			calculate=false
			break
			;;
		c)
			calculate=true
			;;
		m)
			if [ ${#OPTARG} -ne 3 ]
			then
				echo "error: month should be in the form of: Oct, Jan, etc."
				exit 1
			fi
			month=$OPTARG
			;;
		y)
			if [ ${#OPTARG} -ne 4 ]
			then
				echo "error: year should be in the form of: 2017, 2025, etc."
				exit 1
			fi
			year=$OPTARG
			;;
		q)
			quiet=true
			;;
		\?)
			echo -e "Usage:
    $0 [options]\n
Log expense options :
    -o\toverwrite last line of budget

Calculate budget option:
    -c\twill calculate total expense for valid entries
      \tDefault: total expense for current year
    -q\tquite mode, silence recap of expenses
    -y\tspecify year to calculate within
      \tDefault: current year
    -m\tspecify month to calculate within" >&2
			exit 1
			;;
		:)
			echo "Option -$OPTARG requires an argument." >&2
			exit 1
			;;
	esac
done

if $calculate
then
	total=`grep -i "$month $year \d" $filename | awk '{print $3}' | paste -sd+ - | bc`
	if ! $quiet
	then
		grep -i "$month $year" $filename
	fi
	echo "Total: $total"
else
	echo "Entries in the form of: <VALUE> <CATEGORY> <COMMMENT (optional)>"
	while true
	do	
		read statement
		echo `date "+%b %Y"` $statement >> $filename
	done
fi
