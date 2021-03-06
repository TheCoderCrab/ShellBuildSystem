#!/bin/bash

# Uncomment for additional debug info
# SBS_DEBUG=1

# TODO: rewrite this in python3
# It isn't a joke

SBS_DIR=${SBS_DIR:-"${HOME}/.local/share/sbs/"}

source ${SBS_DIR}/exit_code.bash
source ${SBS_DIR}/term.bash
source ${SBS_DIR}/colors.bash

debug "Started sbs"

PROJECT_DIR=${PROJECT_DIR:-$PWD}
SBSRC=${SBSRC:-"${PROJECT_DIR}/sbsrc"}
PROJECT_FILE=${PROJECT_FILE:-"${PROJECT_DIR}/sbs.project"}
SUB_PROJECT_RET=${SUB_PROJECT_RET:-"${PROJECT_DIR}/.sbs/sub_proj_ret"}
LAST_BUILD_FILE=${LAST_BUILD_FILE:-"${PROJECT_DIR}/.sbs/last_build"}
if [[ -f ${LAST_BUILD_FILE} ]]; then
    LAST_BUILD_TIME=${LAST_BUILD_TIME:-$(cat ${LAST_BUILD_FILE})}
else
    LAST_BUILD_TIME=${LAST_BUILD_TIME:-0}
fi

debug "Initialized sbs variables"
debug "Last build time ${LAST_BUILD_TIME}"

cd ${PROJECT_DIR}

mkdir -p ${PROJECT_DIR}/.sbs

[[ -f ${SBSRC} ]] && source ${SBSRC}


debug "Sbs is in debug mode"
debug "Last build: ${LAST_BUILD_TIME}"


_IS_SUB_PROJECT=${_IS_SUB_PROJECT:-0}

if [[ ${_IS_SUB_PROJECT} -eq 0 ]]; then
    print "${bold}${fg_green}Started sbs"
fi

if [[ -f ${PROJECT_FILE} ]]; then
    print "${bold}${fg_green}Reading project file..."
    source ${PROJECT_FILE}
else
    error "${underline}$(basename ${PROJECT_FILE})${end_underline} file not found!"
    exit ${exit_error}
fi

# Set default values
CC=${CC:-"/bin/gcc"}
CXX=${CXX:-"/bin/g++"}
AS=${AS:-"/bin/nasm"}
LINKER=${LINKER:-"/bin/g++"}
STATIC_LINKER=${STATIC_LINKER:-"/bin/ar"}
CFLAGS=${CFLAGS:-""}
CXXFLAGS=${CXXFLAGS:-""}
CCFLAGS=${CCFLAGS:-""}
ASFLAGS=${ASFLAGS:-""}
LINKFLAGS=${LINKFLAGS:-""}
CEXTENSIONS=${CEXTENSIONS:-".c"}
CXXEXTENSIONS=${CXXEXTENSIONS:-".cc .cxx .cpp .c++"}
ASEXTENSIONS=${ASEXTENSIONS:-".s .asm .as"}
SRC=${SRC:-"${PROJECT_DIR}/src/"}
ADDITIONAL_SOURCES=${ADDITIONAL_SOURCES:-""}
INCLUDE=${INCLUDE:-"${PROJECT_DIR}/include"}
PUBLIC_INCLUDE=${PUBLIC_INCLUDE:-""}
TARGET=${TARGET:-"out"}
TYPE=${TYPE:-"exec"}
BUILD_TYPE=${BUILD_TYPE:-"debug"}
BUILD_DIR=${BUILD_DIR:-"${PROJECT_DIR}/build/"}
SUB_PROJECTS=${SUB_PROJECTS:-""}
LIBRARIES=${LIBRARIES:-""}
LIB_DIRS=${LIB_DIRS:-""}

print "${bold}${fg_green}Preparing to build target: \"${fg_blue}${TARGET}${fg_green}\"..."

# Define extended variables
_RBDIR=${_RBDIR:-"${BUILD_DIR}/${BUILD_TYPE}/"}
_BDIR=${_BDIR:-"${_RBDIR}/obj"}

mkdir -p ${_RBDIR}
mkdir -p ${_BDIR}

# Convert some variables into lists
export IFS=${IFS:-" "}
read -ra _CEXT   <<< "${CEXTENSIONS}"
read -ra _CXXEXT <<< "${CXXEXTENSIONS}"
read -ra _ASEXT  <<< "${ASEXTENSIONS}"
read -ra _SRC    <<< "${SRC}"
read -ra _ASRC   <<< "${ADDITIONAL_SOURCES}"
read -ra _INC    <<< "${INCLUDE}"
read -ra _PINC   <<< "${PUBLIC_INCLUDE}"
read -ra _SPR    <<< "${SUB_PROJECTS}"
read -ra _LIBS   <<< "${LIBRARIES}"
read -ra _LDIRS  <<< "${LIB_DIRS}"


if [[ ${TYPE} = "exec" ]]; then
    OUT_NAME="${TARGET}"
elif [[ ${TYPE} = "slib" ]]; then
    OUT_NAME="lib${TARGET}.a"
elif [[ ${TYPE} = "dlib" ]]; then
    CCFLAGS+=" -fPIC"
    OUT_NAME="lib${TARGET}.so"
else
    error "Invalid build type: ${TYPE}"
    exit ${exit_error}
fi

OUT="${_RBDIR}/${OUT_NAME}"

# All the sources

C_SOURCES=()
CXX_SOURCES=()
AS_SOURCES=()

for SOURCE_DIR in ${_SRC[@]}; do
    mkdir -p ${SOURCE_DIR}
    debug "Iterating through source dir: ${SOURCE_DIR}"
    for CEXT in ${_CEXT[@]}; do
        debug "Iterating through C extension: ${CEXT}"
        for SOURCE in $(find ${SOURCE_DIR} -type f -name "*${CEXT}"); do
            debug "Found C source file: ${SOURCE}"
            C_SOURCES+=("${SOURCE}")
        done
    done
    for CXXEXT in ${_CXXEXT[@]}; do
        debug "Iterating through C++ extension: ${CXXEXT}"
        for SOURCE in $(find ${SOURCE_DIR} -type f -name "*${CXXEXT}"); do
            debug "Found C++ source file: ${SOURCE}"
            CXX_SOURCES+=("${SOURCE}")
        done
    done
    for ASEXT in ${_ASEXT[@]}; do
        debug "Iterating through AS extension: ${ASEXT}"
        for SOURCE in $(find ${SOURCE_DIR} -type f -name "*${ASEXT}"); do
            debug "Found AS source file: ${SOURCE}"
            AS_SOURCES+=("${SOURCE}")
        done
    done
done

debug "Source file count: C: ${#C_SOURCES[@]}, C++: ${#CXX_SOURCES[@]}, AS: ${#AS_SOURCES[@]}, Add: ${#_ASRC[@]}"

if [[ ${#_ASRC[@]} -eq 0 && ${#C_SOURCES[@]} -eq 0 &&\
      ${#CXX_SOURCES[@]} -eq 0 && ${#AS_SOURCES[@]} -eq 0 ]]; then
    error "No source file found!"
    exit ${exit_error}
fi

# Check if compilers, assembler and linker exists

if [[ $(command -v ${CC}) ]]; then
    print "${bold}${fg_green}C Compiler: ${CC} found"
else
    error "C Compiler: ${CC} not found!"
    exit ${exit_error}
fi

if [[ $(command -v ${CXX}) ]]; then
    print "${bold}${fg_green}C++ Compiler: ${CXX} found"
else
    error "C++ Compiler: ${CXX} not found!"
    exit ${exit_error}

fi

if [[ $(command -v ${AS}) ]]; then
    print "${bold}${fg_green}Assembler: ${AS} found"
else
    error "Assembler: ${AS} not found!"
    exit ${exit_error}
fi

# Build all subprojects

for PROJ in ${_SPR[@]}; do
    __PROJECT_NAME=$(basename $PROJ)
    if [[ ${PROJ:0:1} = '/' ]]; then
        debug "Subproject ${__PROJECT_NAME} is defined relative to root"
        __SUB_PROJ_DIR=${PROJ}
    else
        debug "Subproject ${__PROJECT_NAME} is defined relative to $(basename ${PROJECT_DIR})"
        __SUB_PROJ_DIR="${PROJECT_DIR}/${PROJ}"
    fi
    print "${fg_green}${bold}Building subproject \"${fg_blue}${__PROJECT_NAME}${fg_green}\""
    env -i SBS_DEBUG=${SBS_DEBUG} PATH="${PATH}" TERM="${TERM}" PROJECT_DIR="${__SUB_PROJ_DIR}" SBS_DIR="${SBS_DIR}"\
    PROJECT_FILE="${__SUB_PROJ_DIR}/$(basename ${PROJECT_FILE})" SBSRC=${SBSRC}                                     \
    CC="${CC}" CXX="${CXX}" AS="${AS}" LINKER="${LINKER}" CEXTENSIONS="${CEXTENSIONS}"                               \
    CXXEXTENSIONS="${CXXEXTENSIONS}" ASEXTENSIONS="${ASEXTENSIONS}" BUILD_TYPE="${BUILD_TYPE}"                        \
    BUILD_DIR="${BUILD_DIR}/${__PROJECT_NAME}" _IS_SUB_PROJECT=1 CFLAGS="${CFLAGS}" LAST_BUILD_TIME=${LAST_BUILD_TIME} \
    CXXFLAGS="${CXXFLAGS}" CCFLAGS="${CCFLAGS}" ASFLAGS="${ASFLAGS}" SUB_PROJECT_RET="${SUB_PROJECT_RET}"               \
    bash ${SBS_DIR}/sbs.bash
    if [[ $? -ne 0 ]]; then
        error "Subproject ${__PROJECT_NAME} didn't execute properly"
        exit ${exit_error}
    fi
    source ${SUB_PROJECT_RET}
    if [[ ${_SPR_TYPE} != "exec" ]]; then # if lib
        print "${bold}${fg_green}Adding subproject ${fg_blue}${__PROJECT_NAME}${fg_green} as a library"
        _PINC+=("${_SPR_INCLUDE[@]}")
        _LIBS+=("${_SPR_TARGET}")
        _LDIRS+=("${_SPR_BUILD_DIR}")
    fi
done

# Build self

INCLUDE_FLAGS=""
LIB_DIRS_FLAGS=""
LIB_FLAGS=""
OBJECTS=""

for INC in ${_INC[@]} ${_PINC[@]}; do
    INCLUDE_FLAGS+=" -I${INC}"
done

for LIB_DIR in ${_LDIRS[@]}; do
    LIB_DIRS_FLAGS+=" -L${LIB_DIR}"
done

for LIB in ${_LIBS[@]}; do
    LIB_FLAGS+=" -l${LIB}"
done

debug " Include flags: \"${INCLUDE_FLAGS}\""

RELINK=0

compile() {
    if [[ ${#} -ne 1 ]]; then
        error "compile got invalid arguments"
        exit -1
    fi
    SOURCE_OUT="${_BDIR}/${SOURCE//\//$'_'}.o"
    SOURCE_EXT="${SOURCE##*.}"
    OBJECTS+=" ${SOURCE_OUT}"
    SOURCE_MODIF=$(stat -c %Y ${SOURCE})

    # I think no ne has a file name containing '$&²²kuyfttuyrfi_uytf&'
    if [[ ${_CEXT[@]} =~ "${SOURCE_EXT}" ]]; then
        IFS=" " read -d "$&²²kuyfttuyrfi_uytf&" -ra DEP_ALL_INCLUDES_L <<< $(${CC}  ${INCLUDE_FLAGS} ${CCFLAGS} ${CFLAGS}   -E -H ${SOURCE} 2>&1 > /dev/null)
    elif [[ ${_CXXEXT[@]} =~ "${SOURCE_EXT}" ]]; then
        IFS=" " read -d "$&²²kuyfttuyrfi_uytf&" -ra DEP_ALL_INCLUDES_L <<< $(${CXX} ${INCLUDE_FLAGS} ${CCFLAGS} ${CXXFLAGS} -E -H ${SOURCE} 2>&1 > /dev/null)
    fi
    # TODO: Implement header change check for assembly
    HEADER_CHANGED=0
    if [[ ! (${_ASEXT[@]} =~ ${SOURCE_EXT}) ]]; then
        debug "Dependecies: ${DEP_ALL_INCLUDES_L[@]}"
        for LINE in ${DEP_ALL_INCLUDES_L[@]}; do
            if [[ ${LINE:0:1} = '.' ]]; then
                continue
            fi
            HEADER=${LINE}
            HEADER_MODIF=$(stat -c %Y ${HEADER} 2> /dev/null)
            debug "Checking file: ${HEADER}"
            if [[ ${HEADER_MODIF} -gt ${LAST_BUILD_TIME} ]]; then
                debug "Changed header file: ${HEADER}"
                HEADER_CHANGED=1
                break
            fi
        done
    fi
    if [[ ! -f ${SOURCE_OUT} || ${SOURCE_MODIF} -gt ${LAST_BUILD_TIME} || HEADER_CHANGED -ne 0 ]]; then
        RELINK=1
        if [[ ${_CEXT[@]} =~ "${SOURCE_EXT}" ]]; then
            print " ${bold}${fg_yellow}=> ${fg_green}Compiling $(basename ${SOURCE})"
            CMD="${CC} -c ${INCLUDE_FLAGS} ${CFLAGS} ${CCFLAGS} ${SOURCE} -o ${SOURCE_OUT}"
            ${CMD}
            if [[ $? -ne 0 ]]; then
                error "Failed to compile: ${SOURCE}"
                error "While executing: "${CMD}""
                exit ${exit_error}
            fi
        elif [[ ${_CXXEXT[@]} =~ "${SOURCE_EXT}" ]]; then
            print " ${bold}${fg_yellow}=> ${fg_green}Compiling $(basename ${SOURCE})"
            CMD="${CXX} -c ${INCLUDE_FLAGS} ${CXXFLAGS} ${CCFLAGS} ${SOURCE} -o ${SOURCE_OUT}"
            ${CMD}
            if [[ $? -ne 0 ]]; then
                error "Failed to compile: ${SOURCE}"
                error "While executing: "${CMD}""
                exit ${exit_error}
            fi
        elif [[ ${_ASEXT[@]} =~ "${SOURCE_EXT}" ]]; then
            print " ${bold}${fg_yellow}=> ${fg_green}Assembling $(basename ${SOURCE})"
            CMD="${AS} ${INCLUDE_FLAGS} ${ASFLAGS} ${SOURCE} -o ${SOURCE_OUT}"
            ${CMD}
            if [[ $? -ne 0 ]]; then
                error "Failed to assemble: ${SOURCE}"
                error "While executing: "${CMD}""
                exit ${exit_error}
            fi
        fi
    else
        print " ${bold}${fg_blue}=> ${fg_green} Skipping $(basename ${SOURCE}), already up to date"
    fi
}

for SOURCE in ${_ASRC[@]}; do
    compile ${SOURCE}
done

for SOURCE in ${C_SOURCES[@]}; do
    compile ${SOURCE}
done

for SOURCE in ${CXX_SOURCES[@]}; do
    compile ${SOURCE}
done

for SOURCE in ${AS_SOURCES[@]}; do
    compile ${SOURCE}
done

if [[ ${RELINK} -ne 0 || ! -f ${OUT} ]]; then
    if [[ ${TYPE} = "exec" ]]; then
        print " ${bold}${fg_yellow}=> ${fg_green}Linking executable: ${fg_blue}$(basename ${OUT})${fg_green}..."
        CMD="${LINKER} ${LINKFLAGS} ${OBJECTS} ${LIB_DIRS_FLAGS} ${LIB_FLAGS} -o ${OUT}"
    elif [[ ${TYPE} = "slib" ]]; then
        print " ${bold}${fg_yellow}=> ${fg_green}Generating static library: ${fg_blue}$(basename ${OUT})${fg_green}..."
        CMD="${STATIC_LINKER} crf "${_RBDIR}/lib${TARGET}.a" ${OBJECTS}"
    elif [[ ${TYPE} = "dlib" ]]; then
        print " ${bold}${fg_yellow}=> ${fg_green}Linking shared library: ${fg_blue}$(basename ${OUT})${fg_green}..."
        CMD="${LINKER} -shared ${LINKFLAGS} ${OBJECTS} ${LIB_DIRS_FLAGS} ${LIB_FLAGS} -o ${OUT}"
    fi

    ${CMD}
    if [[ $? -ne 0 ]]; then
        error "Linking failed!"
        error "While executing: ${CMD}"
        exit ${exit_error}
    fi
else
    print " ${bold}${fg_blue}=> ${fg_green} Skipping ${OUT}, already up to date"
fi

debug "Is sub project ${_IS_SUB_PROJECT}"
if [[ ${_IS_SUB_PROJECT} -eq 1 ]]; then
    ABSOLUTE_INCLUDE=""
    for PINC in ${_PINC[@]}; do
        if [[ ${PINC:0:1} = "/" ]]; then
            ABSOLUTE_INCLUDE+=" ${PINC}"
        else
            ABSOLUTE_INCLUDE+=" ${PWD}/${PINC}"
        fi
    done
    debug "Passing results to parent project"
    printf "_SPR_TYPE=${TYPE}\n_SPR_INCLUDE=(${ABSOLUTE_INCLUDE})\n_SPR_TARGET=${TARGET}\n_SPR_BUILD_DIR=${_RBDIR}\n" > ${SUB_PROJECT_RET}
else
    debug "Writing last build date"
    echo $(date +%s) > ${LAST_BUILD_FILE}
fi

print "${bold}${fg_green}Done building project: ${TARGET}" 
