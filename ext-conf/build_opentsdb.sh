#!/bin/bash -x
packageName=${packageName:-mapr-opentsdb}
sourceVersion=${sourceVersion:-2.4.0}
ebfVersion=${ebfVersion:-0}
packageVersion=${packageVersion:-${sourceVersion}.${ebfVersion}}
repoName=${repoName:-opensource}
isRelease=${isRelease:-}
maprVersion=${maprVersion:-6.1.0-mapr}
kafkaVersion=${kafkaVersion:-1.1.1-mapr-1901}
hadoopVersion=${hadoopVersion:-2.7.0-mapr-1808}
useMaprSnapshots=${useMaprSnapshots:-0}
releaseArgs=${releaseArgs:-"OPENTSDB_BRANCH_NAME=mapr-v${packageVersion}-mep6x MAPR_VERSION=${maprVersion} KAFKA_VERSION=${kafkaVersion} USE_MAPR_SNAPSHOTS=${useMaprSnapshots} HADOOP_VERSION=${hadoopVersion}"}
releaseRepoName=${releaseRepoName:-opensource.release}
ECHONUMBER=${ECONUMBER:-NONE}
privatePkgBranch=${privatePkgBranch:-MEP-4.0.0}
WORKSPACE=${WORKSPACE:-/home/lars/src/build/opentsdb}


export PROJECT=${packageName}-${packageVersion}
export BLD_PROJECT=${packageName}-${sourceVersion}
export CN_NAME="jenkins-temp-${PROJECT}"
export RELEASE_VER=${packageVersion}


#
# globals
#

export JDK8_HOME=/opt/jdk-1.8.0
export JAVA_HOME=$JDK8_HOME
export PREPEND_PATH="${JAVA_HOME}/bin:"


export TZ='America/Los_Angeles'
if [ -z "$DEBUG" ] && [ -z "$DEVELOPMENT_BUILD" ]; then
    export ID=$(ssh root@10.10.1.50 date "+%Y%m%d%H%M")
else
    export ID=$(date "+%Y%m%d%H%M")
fi
export BUILD_TAG=mapr-t${ID}-b${BUILD_NUMBER};
export JOB=$(echo $JOB_NAME | awk -F/ '{print $1}')
export DIST="/usr/local/jenkins/workspace/${JOB}/label/${NODE_NAME}/${repoName}/${PROJECT}/dist"


#
# RedHat globals
#
if [ -z "$(uname -a | grep -i ubuntu)" ]; then
cat > ${WORKSPACE}/properties.txt << EOL
ARTIFACTORY_REPONAME=eco-rpm
ARTIFACTORY_PATH=releases/opensource/redhat/
PACKAGE_TYPE=*.rpm
BUILD_DIR=${BUILD_TAG}
EOL

    #BASE_IMAGE=maprdocker.lab/mapr:centos61-java7-ecosystem-150515

    #BASE_IMAGE=maprdocker.lab/centos7-java8-build
    #BASE_IMAGE=maprdocker.lab/centos7_installer_spyglass-java8:latest
    BASE_IMAGE=maprdocker.lab/centos7-gcc7_installer_spyglass-proto3-java11-spyglass:latest

    EXTRA_CMD="rvm install 2.7.1 --disable-binary"


#
# Ubuntu globals
#
else
cat > ${WORKSPACE}/properties.txt <<EOL
ARTIFACTORY_REPONAME=eco-deb
ARTIFACTORY_PATH=releases/opensource/ubuntu/
PACKAGE_TYPE=*.deb
BUILD_DIR=${BUILD_TAG}
EOL

    #BASE_IMAGE=maprdocker.lab/ubuntu14-java8-build:latest
    #BASE_IMAGE=maprdocker.lab/ubuntu14_installer_spyglass-java8:latest
    BASE_IMAGE=maprdocker.lab/ubuntu16_installer_spyglass-gcc7-proto3-java11-spyglass

    EXTRA_CMD="echo there is no extra cmd"

fi

#
# maven settings
#
if [ "${isRelease}" = "false" ]; then
    echo "Is this a release? -> ${isRelease}"

    export MAPR_MIRROR=central
    export MAVEN_CENTRAL=http://maven.corp.maprtech.com/nexus/content/groups/public/
    export MAPR_MVN_BASE=http://admin:admin123@maven.corp.maprtech.com/nexus/content
    export MAPR_CENTRAL=${MAPR_MVN_BASE}/groups/public
    export MAPR_RELEASES_REPO=${MAPR_MVN_BASE}/repositories/releases
    export MAPR_SNAPSHOTS_REPO=${MAPR_MVN_BASE}/repositories/snapshots
    
    # only use released artifacts
    export MAPR_MAVEN_REPO=${MAPR_CENTRAL}

    export RELEASE_ARGS="${releaseArgs}"
else
    echo "Is this a release? -> ${isRelease}"

    export MAPR_MIRROR=central
    export MAVEN_CENTRAL=http://10.10.100.99:8081/nexus/content/groups/public/
    export MAPR_MVN_BASE=http://admin:admin123@maven.corp.maprtech.com/nexus/content
    export MAPR_CENTRAL=${MAPR_MVN_BASE}/groups/public
    export MAPR_RELEASES_REPO=${MAPR_MVN_BASE}/repositories/releases
    export MAPR_SNAPSHOTS_REPO=${MAPR_MVN_BASE}/repositories/snapshots
    export MAPR_MAVEN_REPO=${MAPR_RELEASES_REPO}
    
    export MAPR_MIRROR=central
    export MAVEN_CENTRAL=http://maven.corp.maprtech.com/nexus/content/groups/public/
    export MAPR_MVN_BASE=http://admin:admin123@maven.corp.maprtech.com/nexus/content
    export MAPR_CENTRAL=${MAPR_MVN_BASE}/groups/public
    export MAPR_RELEASES_REPO=${MAPR_MVN_BASE}/repositories/releases
    export MAPR_SNAPSHOTS_REPO=${MAPR_MVN_BASE}/repositories/snapshots

    export RELEASE_ARGS="${releaseArgs}"

fi

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


if [ -n "$DEBUG" ]; then
    INTERACTIVE_BUILD=${INTERACTIVE_BUILD:-"-i -t"}
    BUILD_CMD_OPT=""
    BUILD_CMD=""
else
    INTERACTIVE_BUILD=""
    BUILD_CMD_OPT="-c"
    BUILD_CMD=" echo ====== ; \
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
        make ${BLD_PROJECT}-info; make ${BLD_PROJECT} ${RELEASE_ARGS} TIMESTAMP=${ID};"
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
              --rm=true \
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
        if [ -e /root/rpmsigning/rpmsign.exp ]; then
            echo Doing RPM signing
            echo Perform signing operation now
            expect -f /root/rpmsigning/rpmsign.exp ${DIST}/*.rpm
            if [ $? -ne 0 ]; then
                echo "RPM signing failed!"
            fi
        else
            echo "Skipping RPM signing  .."
        fi
    fi
fi
