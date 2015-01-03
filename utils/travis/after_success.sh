#!/bin/bash
set -o posix

function attention_echo {
	echo -e "\n******************************************"
	echo -e "*\t$1 *"
	echo -e "******************************************\n"
}

# The possible arguments to pass to this script
ARG_PUBLISH="--publish"

# Default project name (no spaces)
NAME_PROJECT="Default_Project_Name"
# If there is a T_NAME_PROJECT, assign it to NAME_PROJECT
if [ ! -z $T_NAME_PROJECT ]
then
	NAME_PROJECT=${T_NAME_PROJECT}
else
	attention_echo "No T_NAME_PROJECT set"
fi

# Target names
TARGET_PROJECT=${NAME_PROJECT}_exec
TARGET_GTEST=${NAME_PROJECT}_GTest

# Some directories
DIR_PROJECT_ROOT=$(dirname "$(readlink -f $0)")
DIR_PROJECT_ROOT=${DIR_PROJECT_ROOT}/../..
DIR_BUILD=${DIR_PROJECT_ROOT}/build
DIR_SRC=${DIR_PROJECT_ROOT}/src
DIR_BUILD_SRC=${DIR_BUILD}/src
DIR_BUILD_TEST=${DIR_BUILD}/test
DIR_REPORTS=${DIR_BUILD}/reports
DIR_REPORTS_CPPLINT=${DIR_REPORTS}/cpplint-reports
DIR_REPORTS_CPPCHECK=${DIR_REPORTS}/cppcheck-reports
DIR_REPORTS_GCOVR=${DIR_REPORTS}/gcovr-reports
DIR_GCOVR_FILES=${DIR_BUILD_SRC}/CMakeFiles/${TARGET_PROJECT}.dir/
DIR_UTILS=${DIR_PROJECT_ROOT}/utils

function success_exit {
	attention_echo "Finished build script"
	exit 0
}

function publish_doxygen {
	attention_echo "Publish doxygen script start"

	pushd ${DIR_PROJECT_ROOT}
	mkdir push_to_ghpages
	cp -Rf ./build/doc/html/ ./push_to_ghpages/
	cp -Rf ./build/reports/ ./push_to_ghpages/
	pushd ./push_to_ghpages/
	mv html/ doxygen/

	git config --global user.email "travis@travis-ci.org"
	git config --global user.name "Travis-CI"

	git clone --quiet --branch=gh-pages https://${GH_TOKEN}@${GH_REF} gh-pages > /dev/null 2>&1 # Muted for security (personal access token)

	cd gh-pages/
	git rm -rf ./doxygen/
	git rm -rf ./reports/
	cd ..
	mv doxygen/ gh-pages/
	mv reports/ gh-pages/
	cd gh-pages/

	git add --all
	git commit -m "Latest documentation and reports. Auto-pushed from travis. Build $TRAVIS_BUILD_NUMBER"

	git remote rm origin
	git remote add origin https://${GH_USR}:${GH_TOKEN}@${GH_REF} > /dev/null 2>&1 # Muted for security (personal access token)

	git push -fq origin gh-pages > /dev/null 2>&1 # Muted for security (personal access token)
	popd
}

function do_cppcheck {
	attention_echo "cppcheck"

	mkdir -p ${DIR_REPORTS_CPPCHECK} || exit $?

	# Generate cppcheck xml
	cppcheck -v --enable=all ${DIR_SRC} -I${DIR_SRC} --xml-version=2 2> cppcheck-only-result.xml

	# Generate html from it
	${DIR_UTILS}/cppcheck-htmlreport.py\
		--file=cppcheck-only-result.xml\
		--report-dir=${DIR_REPORTS_CPPCHECK}\
		--source-dir=${DIR_PROJECT_ROOT}\
		--title=${NAME_PROJECT}
}

function do_cpplint {
	attention_echo "cpplint.py"

	mkdir -p ${DIR_REPORTS_CPPLINT} || exit $?

	# Generate cppcheck-style xml from cpplint output
	${DIR_UTILS}/cpplint.py --filter=-whitespace,-legal ${DIR_SRC}/*.cpp 2>&1|\
		sed 's/"/\&quot;/g' >&1| sed 's/</\&lt;/g' >&1| sed 's/>/\&gt;/g' >&1|\
		sed "s/'/\&apos;/g" >&1| sed 's/\&/\&amp;/g' >&1|\
		${DIR_UTILS}/cpplint_to_cppcheckxml.py &> cpplint-cppcheck-result.xml

	# Generate html from it
	${DIR_UTILS}/cppcheck-htmlreport.py\
		--file=cpplint-cppcheck-result.xml\
		--report-dir=${DIR_REPORTS_CPPLINT}\
		--source-dir=${DIR_PROJECT_ROOT}\
		--title=${NAME_PROJECT}

	# Change Cppcheck things to cpplint
	sed -i 's/Cppcheck/cpplint/g' ${DIR_REPORTS_CPPLINT}/index.html
	sed -i 's/a\ tool\ for\ static\ C\/C++\ code\ analysis/an\ open\ source\ lint\-like\ tool\ from\ Google/g' ${DIR_REPORTS_CPPLINT}/index.html
	sed -i 's/http:\/\/cppcheck.sourceforge.net/http:\/\/google\-styleguide.googlecode.com\/svn\/trunk\/cpplint\/cpplint.py/g' ${DIR_REPORTS_CPPLINT}/index.html
	sed -i 's/IRC: <a href=\"irc:\/\/irc.freenode.net\/cppcheck\">irc:\/\/irc.freenode.net\/cppcheck<\/a>/\ /g' ${DIR_REPORTS_CPPLINT}/index.html
}

function do_valgrind {
	attention_echo "Valgrind"

	# Project valgrind report
	valgrind --xml=yes\
		--xml-file=${DIR_REPORTS}/valgrind-${TARGET_PROJECT}-report.xml\
		${DIR_BUILD_SRC}/${TARGET_PROJECT}

	# Test suite valgrind report + Test report
	valgrind --xml=yes\
		--xml-file=${DIR_REPORTS}/valgrind-${TARGET_GTEST}-report.xml\
		${DIR_BUILD_TEST}/${TARGET_GTEST}\
		--gtest_output=xml:${DIR_REPORTS}/gtest-report.xml
}

function do_gcovr {
	attention_echo "gcovr"

	mkdir -p ${DIR_REPORTS_GCOVR} || exit $?

	gcovr --verbose\
		--root=${DIR_GCOVR_FILES}\
		--filter=${DIR_PROJECT_ROOT}/src\
		--html --html-details --output=${DIR_REPORTS_GCOVR}/index.html
}

function code_analysis {
	do_cppcheck
	do_cpplint
	do_valgrind
	do_gcovr
}

function usage {
	echo "The correct usage of this script:"
	echo -e "\t./after_success.sh"
	echo -e "\t./after_success.sh --publish"
	echo ""
	exit 2
}

#########################################
################ "Main" #################
#########################################

attention_echo "after_success : ${NAME_PROJECT}"

# If there is no build directory, exit
if [ ! -d "$DIR_BUILD" ]
then
	attention_echo "No build directory! Exiting..."
	exit 3
fi

# If the first argument is empty or isn't ARG_PUBLISH
if [ ! -z $1 ] && [ $1 != ${ARG_PUBLISH} ]
then
	echo -e "Invalid parameter '$1' \n"
	usage
fi

pushd ${DIR_BUILD}

code_analysis

attention_echo "Packing with CPack"

cpack
popd

# If the first argument is what we want
if [ ! -z $1 ] && [ $1 == ${ARG_PUBLISH} ]
then
	attention_echo "cpp-coveralls"

	# Publish to Coveralls
	coveralls --verbose\
		--root ${DIR_PROJECT_ROOT} -E ".*externals*" -E ".*CMakeFiles.*" -E ".*test/.*.cpp.*"

	# Publish Doxygen to gh-pages
	publish_doxygen

# If no argument specified to publish
else
	attention_echo "Not publishing Doxygen/Coveralls"
fi
