#!/bin/bash

function print_success () {
    echo -e "[\x1B[01;32m+\x1B[0m] $1"
}

function print_error () {
    echo -e "[\x1B[01;31m!\x1B[0m] $1"
}

function print_warning () {
    echo -e "[\x1B[01;33m-\x1B[0m] $1"
}

function print_info () {
    echo -e "[\x1B[01;34m*\x1B[0m] $1"
}


function help()
{
   echo "Syntax: ntdissector.sh [-ntds, -system, -outputdir]"
   echo "options:"
   echo "n      Location of NTDS.dit file."
   echo "s   	Location of SYSTEM hive."
   echo "o		Location of the output files."
   echo
}


function check_arguments {
	if [ -z "$ntds" ] || [ -z "$system" ] || [ -z "$outputdir" ]; then	print_error "ntds, system, and outputdir must be supplied."
		help
		exit 1
	fi
}

function is_user_root () {
  if [ "$EUID" -ne 0 ]; then
      print_error "This script needs to be run using sudo"
      exit 1
  fi
}


function change_directory_script () {
  SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
  cd $SCRIPT_DIR
}


function dependencies () {
    print_info "Installing required dependencies"
    apt-get -qq update > /dev/null 
    apt-get -qq install -y git python3-pip python3-venv > /dev/null 
    apt-get -qq -y autoremove > /dev/null 
    apt-get -qq -y clean > /dev/null 
    yes | pip3 install --no-cache-dir -I \
        'virtualenv' \
        -q -q -q --exists-action i
    print_success "Dependencies installed"
}


function create_venv() {    
  if [ -d ".venv" ]; then
      print_warning "Virtual environment '.venv' already exists and will be used"
  else
    print_info "Creating virtualenv for ntdissector"
    python3 -m venv ".venv"
    print_success "virtual env created"
  fi
}


function install_ntdissector () {
  source "./.venv/bin/activate"
  if ! command -v ntdissector &> /dev/null
  then
      print_info "Installing ntdissector"
      git clone --quiet https://github.com/synacktiv/ntdissector.git
      yes | python3 -m pip install ntdissector/. --no-cache-dir -I \
          -q -q -q --exists-action i
  fi
  deactivate
}


function exec_ntdissector () {
  print_info "Executing ntdissector on files provided in to_analyze folder"
  source "./.venv/bin/activate"
  ntdissector -ntds $ntds -system $system -outputdir $outputdir -ts -f all
  print_success "JSON files stored in $outputdir/out"
  print_info "Dumping NTLM hashes"
  python3 $SCRIPT_DIR/ntdissector/ntdissector/tools/user_to_secretsdump.py $outputdir/out/*/*.json > $outputdir/out/ntlm-hashes
  print_info "Parsing NTLM hashes in"
  cat $outputdir/out/ntlm-hashes | cut -d : -f 4 |sort|uniq > $outputdir/out/ntlm-hashes-hashcat
  print_success "NTLM hashes dumped in $outputdir/out/"
  deactivate
}


function main () {
    is_user_root
	check_arguments
    change_directory_script
    dependencies
    create_venv
    install_ntdissector
    exec_ntdissector
}

set -e
trap 'error_handling' EXIT
error_handling() {
  exit_status=$?
  if [ "$exit_status" -ne 0 ]; then
    print_error "There was an error while executing the script (Exit Status: $exit_status)"
  fi
}

while getopts ":hn:s:o:" option; do
   	case $option in
    	h) 
        	help
         	exit;;
      	n)
        	ntds=$OPTARG;;
	  	s)
			system=$OPTARG;;
		o)
			outputdir=$OPTARG;;
     	\?)
         	print_error "Invalid option"
         	exit;;
   	esac
done

main