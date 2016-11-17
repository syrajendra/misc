#!/bin/sh

DRY_RUN=0
USER=`id -u -n`

OS=`uname -s`
MACHINE=`uname -m`
if [ ${OS} = "FreeBSD" ] ; then
    OS_ID=`uname -r | sed -e 's/[-_].*//' | sed -e 's/\..*// '`
elif [ ${OS} = "Darwin" ]; then
    OS_ID=`uname -r`
elif [ $OS = "Linux" ]; then
    if [ -f /etc/redhat-release ]; then
      # Redhat, Centos and similar
      OS_ID=`cat /etc/redhat-release | awk ' { print $1"-"$3 } ' | tr '[:upper:]' '[:lower:]'`
    elif [ -f /etc/os-release ]; then
      # Ubuntu
      OS_ID=`cat /etc/os-release | grep VERSION_ID | awk -F \" '{ print $2 }'`
      OS_ID="ubuntu-${OS_ID}"
    fi
else
  echo "Unknow platform"
  exit 1
fi

###########################################################################################
# Prerequisites:
# On Ubuntu
# 1.
#   $ sudo apt-get install zlib1g-dev
#   For error:  zipimport.ZipImportError: can't decompress data; zlib not available
# 2.
#   $ sudo apt-get install libssl-dev openssl
#   For error: ImportError: cannot import name HTTPSHandler
# 3.
#   $ sudo apt-get update
#   $ sudo apt-get install libmysqlclient-dev
#   For error: EnvironmentError: mysql_config not found
###########################################################################################
# Edit below for different versions of python ###
TOP_DIR="$PWD"
PYTHON_VERSION="2.7.12"
PYTHON_DOWNLOAD_CMD="wget https://www.python.org/ftp/python/2.7.12/Python-2.7.12.tar.xz"
PIP_DOWNLOAD_CMD="wget https://bootstrap.pypa.io/get-pip.py"
PYTHON_MODULES="zeep suds suds_requests MySQL-python django"
###########################################################################################

PYTHON_ZIP_FILE=`basename $(echo "$PYTHON_DOWNLOAD_CMD" | sed s/wget\ //g)`
PYTHON_FILE=`echo $PYTHON_ZIP_FILE | sed s/.tar.*//g`
PIP_FILE=`basename $(echo $PIP_DOWNLOAD_CMD | sed s/wget\ //g)`
SRC=$TOP_DIR/python/${PYTHON_VERSION}/src
BUILD=$TOP_DIR/python/${OS_ID}/${MACHINE}/${PYTHON_VERSION}/build
TIMESTAMP=`date +%s`
LOG_FILE=$BUILD/python_${TIMESTAMP}.log
LOG_CMD=" >> $LOG_FILE 2>&1 "
INSTALL=$TOP_DIR/$OS/$OS_ID/${MACHINE}/python/$PYTHON_VERSION

if [ $OS = "Linux" ]; then
	MAKE="make"
	# CPUs = Threads per core X cores per socket X sockets
	CORES_PER_CPU=`cat /proc/cpuinfo | grep -m 1 'cpu cores' | awk '{ print $4 }'`
	TOTAL_CPUS=`cat /proc/cpuinfo | grep processor | wc -l`
	if [ "$CORES_PER_CPU" = "0" ]; then
		CORES_PER_CPU=1
	fi
	CPUS=$(($CORES_PER_CPU * $TOTAL_CPUS))
elif [ $OS = "FreeBSD" ]; then
	MAKE="gmake"
	CPUS=`sysctl hw.ncpu|sed s/hw.ncpu:\ //g`
else
	echo "Platform not supported"
	exit 1
fi

run_cmd() {
	echo "CMD: $@"
	if [ "x$DRY_RUN" = "x" ] || [ "x$DRY_RUN" = "x0" ]; then
		if eval "$@"; then
			echo "Status : Success"
		else
			echo "Status : Failed"
			exit 1
		fi
	else
		echo "Dry run success"
	fi
}

init() {
	run_cmd "mkdir -p $SRC"
	run_cmd "mkdir -p $BUILD"
}

get_src() {
	# Get source
	if [ ! -f $SRC/$PYTHON_ZIP_FILE ]; then
		run_cmd "cd $SRC && $PYTHON_DOWNLOAD_CMD $LOG_CMD"
	fi

	if [ ! $SRC/$PIP_FILE ]; then
		run_cmd "cd $SRC && $PIP_DOWNLOAD_CMD $LOG_CMD"
	fi

	cmd="cd $SRC && tar -xpvf $PYTHON_ZIP_FILE"
	if [ ! -d $SRC/$PYTHON_FILE ]; then
		run_cmd "$cmd $LOG_CMD"
	fi
}


build_install() {
	# Build
	cmd="cd $BUILD && $SRC/$PYTHON_FILE/configure -enable-shared --with-zlib=/usr/include --prefix=$INSTALL LDFLAGS=-Wl,-rpath=$INSTALL/lib --enable-unicode=ucs4"
	run_cmd "$cmd $LOG_CMD"

	cmd="cd $BUILD && $MAKE -j $CPUS"
	run_cmd "$cmd $LOG_CMD"
	run_cmd "mkdir -p $INSTALL"
	cmd="cd $BUILD && $MAKE install"
	run_cmd "$cmd $LOG_CMD"
	echo "Successfully installed python-$PYTHON_VERSION"
}

install_pip() {
	# Install pip
	PYTHON=$INSTALL/bin/python
	if [ -f $PYTHON ]; then
		PIP=$INSTALL/bin/pip
		if [ ! -f $PIP ]; then
			cmd="$PYTHON $SRC/$PIP_FILE"
			run_cmd "$cmd $LOG_CMD"
		else
			echo "Pip command already installed. Skipping"
		fi
	else
		echo "Python-$PYTHON_VERSION not built correctly !!!"
		exit 1
	fi
}

install_modules() {
	# Install modules
	PIP=$INSTALL/bin/pip
	if [ -f $PIP ]; then
		for module in $PYTHON_MODULES; do
			cmd="$PYTHON -x \"import $module\""
			$cmd $LOG_CMD > /dev/null 2>&1
			if [ $? != 0 ]; then
				cmd="$PIP install $module"
				run_cmd "$cmd $LOG_CMD"
				echo "Python module '$module' successfully installed"
			else
				echo "Python module '$module' already installed skipping"
			fi
		done
	else
		echo "Python-$PYTHON_VERSION has not built 'pip' tool correctly !!!"
		exit 1
	fi
}

if [ -d $INSTALL ]; then
	echo "ERROR: Python installation '$INSTALL' already exist"
	echo "Skipping python-$PYTHON_VERSION installation"
	install_pip
	install_modules
else
	echo "Installing python-$PYTHON_VERSION"
	init
	get_src
	build_install
	install_pip
	install_modules
fi
