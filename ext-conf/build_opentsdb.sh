#!/bin/bash -x
packageName=${packageName:-mapr-opentsdb}
sourceVersion=${sourceVersion:-2.4.0}
branchName=${branchName:-mapr-v${packageVersion}-mep6x}
ebfVersion=${ebfVersion:-0}
packageVersion=${packageVersion:-${sourceVersion}.${ebfVersion}}
repoName=${repoName:-opensource}
isRelease=${isRelease:-}
maprVersion=${maprVersion:-6.0.1-mapr}
kafkaVersion=${kafkaVersion:-1.0.1-mapr}
hadoopVersion=${hadoopVersion:-2.7.0-mapr-1506}
useMaprSnapshots=${useMaprSnapshots:-0}
useJarsFromStaging=${useJarsFromStaging:-0}
releaseArgs=${releaseArgs:-"OPENTSDB_BRANCH_NAME=${branchName} MAPR_VERSION=${maprVersion} KAFKA_VERSION=${kafkaVersion} USE_MAPR_SNAPSHOTS=${useMaprSnapshots} HADOOP_VERSION=${hadoopVersion}"}
releaseRepoName=${releaseRepoName:-opensource.release}
ECHONUMBER=${ECONUMBER:-NONE}
privatePkgBranch=${privatePkgBranch:-MEP-4.0.0}
WORKSPACE=${WORKSPACE:-/home/lars/src/build/opentsdb}


export PROJECT=${packageName}-${packageVersion}
export BLD_PROJECT=${packageName}-${sourceVersion}
export CN_NAME="jenkins-temp-${PROJECT}-${branchName}"
export RELEASE_VER=${packageVersion}
export JENKINS_HOST="10.163.161.242"


#
# globals
#

export JDK8_HOME=/opt/jdk-1.8.0
export JAVA_HOME=$JDK8_HOME
export PREPEND_PATH="${JAVA_HOME}/bin:"


export TZ='America/Los_Angeles'
if [ -z "$DEBUG" ] && [ -z "$DEVELOPMENT_BUILD" ]; then
    export ID=$(ssh root@${JENKINS_HOST} date "+%Y%m%d%H%M")
    RM_CONTAINER="true"
else
    export ID=$(date "+%Y%m%d%H%M")
    RM_CONTAINER="false"
fi
export BUILD_TAG=mapr-t${ID}-b${BUILD_NUMBER};
export JOB=$(echo $JOB_NAME | awk -F/ '{print $1}')
export LABEL=${JOB_NAME##*label=}
export DIST="${WORKSPACE}/${repoName}/${PROJECT}/dist"

if [ ! -d "${WORKSPACE}" ]; then
    mkdir -p "${WORKSPACE}"
fi

if [ -f /etc/SuSE-release ] || [ "$LABEL" = "sles1" ]; then
#
# Suse globals
#

cat > ${WORKSPACE}/properties.txt << EOL
ARTIFACTORY_REPONAME=eco-suse
ARTIFACTORY_PATH=releases/opensource/suse/${PROJECT}
PACKAGE_TYPE=*.rpm
BUILD_DIR=${BUILD_TAG}
EOL

    BASE_IMAGE=dfdkr.mip.storage.hpecorp.net/suse12_installer_spyglass-gcc7-proto2-golang1.13-java12-spyglass:latest

    EXTRA_CMD="rvm install 2.7.1 --disable-binary"

#
# RedHat globals
#
elif [ -z "$(uname -a | grep -i ubuntu)" ]; then
cat > ${WORKSPACE}/properties.txt << EOL
ARTIFACTORY_REPONAME=eco-rpm
ARTIFACTORY_PATH=releases/opensource/redhat/${PROJECT}
PACKAGE_TYPE=*.rpm
BUILD_DIR=${BUILD_TAG}
EOL

    #BASE_IMAGE=dfdkr.mip.storage.hpecorp.net/mapr:centos61-java7-ecosystem-150515
    #BASE_IMAGE=dfdkr.mip.storage.hpecorp.net/centos7-java8-build
    #BASE_IMAGE=dfdkr.mip.storage.hpecorp.net/centos7_installer_spyglass-java8:latest
    BASE_IMAGE=dfdkr.mip.storage.hpecorp.net/centos7-gcc7_installer_spyglass-proto2-golang1.13-java12-spyglass:latest

    EXTRA_CMD="rvm install 2.7.1 --disable-binary"


#
# Ubuntu globals
#
else
cat > ${WORKSPACE}/properties.txt <<EOL
ARTIFACTORY_REPONAME=eco-deb
ARTIFACTORY_PATH=releases/opensource/ubuntu/${PROJECT}
PACKAGE_TYPE=*.deb
BUILD_DIR=${BUILD_TAG}
EOL

    #BASE_IMAGE=dfdkr.mip.storage.hpecorp.net/ubuntu14-java8-build:latest
    #BASE_IMAGE=dfdkr.mip.storage.hpecorp.net/ubuntu14_installer_spyglass-java8:latest
    BASE_IMAGE=dfdkr.mip.storage.hpecorp.net/ubuntu14_installer_spyglass-proto2-java8-golang1.13-spyglass:latest


    EXTRA_CMD="echo there is no extra cmd"

fi

#
# maven settings
#
if [ "${isRelease}" = "false" ]; then
    echo "Is this a release? -> ${isRelease}"

    export MAPR_MIRROR=central
    export MAPR_MVN_BASE=http://admin:admin123@df-mvn-dev.mip.storage.hpecorp.net/nexus/content
    export MAPR_CENTRAL=${MAPR_MVN_BASE}/groups/public
    export MAPR_RELEASES_REPO=${MAPR_MVN_BASE}/repositories/releases
    export MAPR_SNAPSHOTS_REPO=${MAPR_MVN_BASE}/repositories/snapshots
    
    # only use released artifacts
    export MAPR_MAVEN_REPO=${MAPR_CENTRAL}

else
    echo "Is this a release? -> ${isRelease}"

    export MAPR_MIRROR=central
    export MAVEN_STAGE=http://df-mvn-stage.mip.storage.hpecorp.net:8081/nexus/content/repositories/releases
    export MAPR_MVN_BASE=http://admin:admin123@df-mvn-dev.mip.storage.hpecorp.net/nexus/content
    export MAPR_CENTRAL=${MAPR_MVN_BASE}/groups/public
    export MAPR_RELEASES_REPO=${MAPR_MVN_BASE}/repositories/releases
    export MAPR_SNAPSHOTS_REPO=${MAPR_MVN_BASE}/repositories/snapshots

    if [ "${useJarsFromStaging}" = "true" ]; then
        export MAPR_MAVEN_REPO=${MAVEN_STAGE}
    else
        export MAPR_MAVEN_REPO=${MAPR_RELEASES_REPO}
    fi
fi

export RELEASE_ARGS="${releaseArgs}"

echo "MAPR_MIRROR=$MAPR_MIRROR" >> env.txt
echo "MAVEN_CENTRAL=$MAVEN_CENTRAL" >> env.txt
echo "MAPR_MVN_BASE=$MAPR_MVN_BASE" >> env.txt
echo "MAPR_CENTRAL=$MAPR_CENTRAL" >> env.txt
echo "MAPR_RELEASES_REPO=$MAPR_RELEASES_REPO" >> env.txt
echo "MAPR_SNAPSHOTS_REPO=$MAPR_SNAPSHOTS_REPO" >> env.txt
echo "MAPR_MAVEN_REPO=$MAPR_MAVEN_REPO" >> env.txt
echo "RELEASE_ARGS=\"$RELEASE_ARGS\"" >> env.txt
echo "BLD_PROJECT=$BLD_PROJECT" >> env.txt
echo "PROJECT=$PROJECT" >> env.txt
echo "privatePkgBranch=$privatePkgBranch" >> env.txt
echo "PREPEND_PATH=${PREPEND_PATH}" >> env.txt
echo "MAPR_VERSION=${maprVersion}" >> env.txt
echo "KAFKA_VERSION=${kafkaVersion}" >> env.txt
echo "HADOOP_VERSION=${hadoopVersion}" >> env.txt
echo "USE_MAPR_SNAPSHOTS=${useMaprSnapshots}" >> env.txt
echo "JAVA_HOME=${JAVA_HOME}" >> env.txt
echo "BUILD_NUMBER=${RELEASE_VER}.${BUILD_NUMBER}" >> env.txt


if [ -n "$NOEXITAFTERBUILD" ]; then
    INTERACTIVE_BUILD="-i -t"
    INTERACTIVE_SHELL="/bin/bash"
else
    INTERACTIVE_SHELL=""
fi

if [ -n "$DEBUG" ]; then
    INTERACTIVE_BUILD=${INTERACTIVE_BUILD:-"-i -t"}
    BUILD_CMD_OPT=""
    BUILD_CMD=""
else
    INTERACTIVE_BUILD="${INTERACTIVE_BUILD:-""}"
    BUILD_CMD_OPT="-c"
    BUILD_CMD=" echo ====== ; \
        npm config set proxy http://web-proxy.corp.hpecorp.net:8080/;\
        npm config set https-proxy http://web-proxy.corp.hpecorp.net:8080/;\
        npm config set http-proxy http://web-proxy.corp.hpecorp.net:8080/;\
        npm config set strict-ssl=false;\
        npm config set loglevel=verbose;\
        echo /root/docker-build-info/gitlog10.txt ; \
        cat /root/docker-build-info/gitlog10.txt ; \
        echo ====== ; \
        echo /root/docker-build-info/tag.txt ; \
        cat /root/docker-build-info/tag.txt ; \
        echo ====== ; \
        echo \$PATH ; \
        PATH=\$PREPEND_PATH:\$PATH ; \
        echo \$PATH ; \
        rm -rf ${PROJECT}; git clone git@github.com:mapr/private-pkg.git ${PROJECT} ; \
        cd ${PROJECT};  \
        git checkout ${privatePkgBranch} ; \
        make ${BLD_PROJECT}-info; make ${BLD_PROJECT} ${RELEASE_ARGS} TIMESTAMP=${ID}; \
        ${INTERACTIVE_SHELL}"
fi

if [ -z "$DEBUG" ]; then
    git log -n 10 > gitlog10.txt
fi

#
# If there's already a container with the same name, remove it.
#
if [ ! -z "$(docker inspect -f {{.State.Running}} ${CN_NAME} 2> /dev/null)" ]; then
    docker rm -f ${CN_NAME}
fi


docker pull ${BASE_IMAGE}
if [ $? -ne 0 ]; then
    echo "Failed to pull image ${BASE_IMAGE}"
    exit 1
fi

#
# build
#
cat ./env.txt

DOCKER_OPTS=" --env-file ./env.txt \
              $INTERACTIVE_BUILD \
              --name="${CN_NAME}" \
              --workdir="/root/${repoName}" \
              --rm=$RM_CONTAINER \
              -v /root/yum-proxy.conf:/etc/yum.conf:ro \
              -v /root/apt-proxy.conf:/etc/apt/apt.conf.d/proxy.conf:ro \
              -v /usr/local/jenkins/workspace/mapr-${PROJECT}-${branchName}/mvncache/repository:/root/.m2/repository:rw \
              -v /root/.m2/settings.xml:/root/.m2/settings.xml:ro \
              -v /root/.gradle/gradle.properties:/root/.gradle/gradle.properties:ro \
              -v /etc/profile.d/proxy.sh:/etc/profile.d/proxy.sh:ro \
              -v /etc/hosts:/etc/hosts:ro \
              -v /etc/resolv.conf:/etc/resolv.conf:ro \
              -v ${WORKSPACE}/${repoName}:/root/${repoName}:rw "

if [ -n "$DEBUG" ]; then
    docker run $DOCKER_OPTS ${BASE_IMAGE} /bin/bash
else
    docker run $DOCKER_OPTS ${BASE_IMAGE} /bin/bash $BUILD_CMD_OPT "$BUILD_CMD"
fi

#
# container cleanup
#
DOCKER_EXIT_CODE=$?

if [ -z "$DEBUG" ] && [ -z "$DEVELOPMENT_BUILD" ]; then
    rm -f ./env.txt

    docker rm -f ${CN_NAME}
fi

if [ $DOCKER_EXIT_CODE != 0 ]; then
    echo "Docker exited badly, look further up the log"
    exit 1
fi

#
# Sign the RPMs
#

if [ -z "$DEBUG" ] && [ -z "$DEVELOPMENT_BUILD" ]; then
    if [ -z "$(uname -a | grep -i ubuntu)" ]; then
        if [ -e "/root/bin/rpmSign.sh" ]; then
            SIGN_CMD="/root/bin/rpmSign.sh ${DIST}/"
        elif [ -e /root/rpmsigning/rpmsign.exp ]; then
            SIGN_CMD="expect -f /root/rpmsigning/rpmsign.exp "${DIST}/*.rpm
        else
            echo "No signing script found"
            exit 1
        fi
        echo "Doing RPM signing"
        echo "Perform signing operation now"
        $SIGN_CMD
        if [ $? -ne 0 ]; then
            echo "RPM signing failed!"
            exit 1
        fi
    else
        echo "Ubuntu signing not done in jenkins job!"
    fi
else
    echo "signing not done in debug/development builds!"
fi
