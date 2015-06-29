CWD=$(shell pwd)
NAME?=$(shell basename ${CWD})
ROOT?=${CWD}
DEPS=$(wildcard ${ROOT}/deps/*/ebin)
APPS=$(wildcard ${ROOT}/ebin)
HOST=$(hostname)
CT_LOG=${ROOT}/logs/ct
COVERTOOL?=deps/covertool/covertool
REBAR?=${ROOT}/rebar -j 4
ERL?=/usr/bin/env erl
TEST_CONFIG?=${ROOT}/test/resources/test
TEST_VM_ARGS?=${ROOT}/test/resources/vm.args
ERLARGS?=-pa ebin -pa ${DEPS} -smp enable -boot start_sasl -s lager
TEST_ERL_ARGS?=${ERLARGS} -args_file ${TEST_VM_ARGS} -config ${TEST_CONFIG}
DIALYZER?=/usr/bin/env dialyzer
DIALYZER_OUT=${NAME}.plt
XREF_OUT=${CT_LOG}/xref.txt
ifdef CT_SUITES
    CT_SUITES_="suites=${CT_SUITES}"
else
    CT_SUITES_=""
endif
ifdef CT_CASE
    CT_CASE_="case=${CT_CASE}"
else
    CT_CASE_=""
endif

all: clean getdeps compile

# Clean all.
clean:
	@${REBAR} clean
	@rm -rf .rebar ebin logs log

# Gets dependencies.
getdeps:
	@${REBAR} get-deps

# Compiles.
compile:
	@${REBAR} compile

# Compiles.
fastcompile:
	@${REBAR} compile skip_deps=true

# Dialyzer plt
${DIALYZER_OUT}:
	${DIALYZER} --verbose --build_plt -pa ${DEPS} --output_plt ${DIALYZER_OUT} \
		--apps kernel \
		stdlib \
		erts \
		compiler \
		hipe \
		crypto \
		edoc \
		gs \
		syntax_tools \
		tools \
		runtime_tools \
		inets \
		xmerl \
		ssl \
		mnesia \
		webtool

# Runs Dialyzer
analyze: compile ${DIALYZER_OUT} xref
	${DIALYZER} --verbose -pa ${DEPS} --plt ${DIALYZER_OUT} -Werror_handling \
		`find ${APP_DIR} -type f -name "${NAME}*.beam" | grep -v SUITE`

# Runs xref
xref:
	${REBAR} skip_deps=true xref

# Generates doc
edoc:
	${REBAR} skip_deps=true doc 

# This one runs without a release.
shell: fastcompile
	${ERL} ${ERLARGS} -boot sasl -config ${ROOT}/priv/example -s safe_bunny -name safe_bunny@${HOST}

# Intended to be run by a CI server.
test: compile #analyze
	@rm -rf ${CT_LOG}
	@mkdir -p ${CT_LOG}
	@find ${ROOT}/src -type f -exec cp {} ${ROOT}/ebin \;
	@find ${ROOT}/test -type f -exec cp {} ${ROOT}/ebin \;
	@ERL_FLAGS="${TEST_ERL_ARGS}" \
	    ERL_AFLAGS="${TEST_ERL_ARGS}" \
	    ${REBAR} -v 3 skip_deps=true ${CT_SUITES_} ${CT_CASE_} ct
	@find ${ROOT}/ebin -type f -name "*.erl" -exec rm {} \;

ci: getdeps test cobertura edoc
	make xref > ${XREF_OUT}

covertool:
	cd deps/covertool && make REBAR=${REBAR} deps
	cd deps/covertool && make REBAR=${REBAR} compile

cobertura: covertool
	echo ${COVERTOOL} -output ${ROOT}/logs/coverage.xml \
	    -cover ${ROOT}/logs/cover.data -src ${ROOT}/src -appname ${NAME}
	${COVERTOOL} -output ${ROOT}/logs/coverage.xml \
	    -cover ${ROOT}/logs/cover.data -src ${ROOT}/src -appname ${NAME}

# If you're a dev, run this target instead of the one above: it will open
# the coverage results on your browser.
devtest: test
	@open ${CT_LOG}/index.html
