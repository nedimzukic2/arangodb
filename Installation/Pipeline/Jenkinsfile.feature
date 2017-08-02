//  -*- mode: groovy-mode

properties(
    [[
      $class: 'BuildDiscarderProperty',
      strategy: [$class: 'LogRotator', artifactDaysToKeepStr: '', artifactNumToKeepStr: '', daysToKeepStr: '3', numToKeepStr: '5']
    ]]
)

def defaultLinux = true
def defaultMac = false
def defaultWindows = false
def defaultBuild = true
def defaultCleanBuild = false
def defaultCommunity = true
def defaultEnterprise = true
def defaultJslint = true
def defaultRunResilience = false
def defaultRunTests = false
def defaultSkipTestsOnError = true
def defaultFullParallel = false

properties([
    parameters([
        booleanParam(
            defaultValue: defaultLinux,
            description: 'build and run tests on Linux',
            name: 'Linux'
        ),
        booleanParam(
            defaultValue: defaultMac,
            description: 'build and run tests on Mac',
            name: 'Mac'
        ),
        booleanParam(
            defaultValue: defaultWindows,
            description: 'build and run tests in Windows',
            name: 'Windows'
        ),
        booleanParam(
            defaultValue: defaultFullParallel,
            description: 'build all os in parallel',
            name: 'fullParallel'
        ),
        booleanParam(
            defaultValue: defaultBuild,
            description: 'build executables',
            name: 'build'
        ),
        booleanParam(
            defaultValue: defaultCleanBuild,
            description: 'clean build directories',
            name: 'cleanBuild'
        ),
        booleanParam(
            defaultValue: defaultSkipTestsOnError,
            description: 'skip Mac & Windows tests if Linux tests fails',
            name: 'skipTestsOnError'
        ),
        booleanParam(
            defaultValue: defaultCommunity,
            description: 'build and run tests for community',
            name: 'Community'
        ),
        booleanParam(
            defaultValue: defaultEnterprise,
            description: 'build and run tests for enterprise',
            name: 'Enterprise'
        ),
        booleanParam(
            defaultValue: defaultJslint,
            description: 'run jslint',
            name: 'runJslint'
        ),
        booleanParam(
            defaultValue: defaultRunResilience,
            description: 'run resilience tests',
            name: 'runResilience'
        ),
        booleanParam(
            defaultValue: defaultRunTests,
            description: 'run tests',
            name: 'runTests'
        )
    ])
])

// build executable
buildExecutable = params.build

// start with empty build directory
cleanBuild = params.cleanBuild

// skip tests on previous error
skipTestsOnError = params.skipTestsOnError

// do everything in parallel
fullParallel = params.fullParallel

// build community
useCommunity = params.Community

// build enterprise
useEnterprise = params.Enterprise

// build linux
useLinux = params.Linux

// build mac
useMac = params.Mac

// build windows
useWindows = params.Windows

// run jslint
runJslint = params.runJslint

// run resilience tests
runResilience = params.runResilience

// run tests
runTests = params.runTests

// restrict builds
restrictions = []

// -----------------------------------------------------------------------------
// --SECTION--                                             CONSTANTS AND HELPERS
// -----------------------------------------------------------------------------

// users
jenkinsMaster = 'jenkins-master@c1'
jenkinsSlave = 'jenkins'

// github repositiory for resilience tests
resilienceRepo = 'https://github.com/arangodb/resilience-tests'

// github repositiory for enterprise version
enterpriseRepo = 'https://github.com/arangodb/enterprise'

// Jenkins credentials for enterprise repositiory
credentials = '8d893d23-6714-4f35-a239-c847c798e080'

// jenkins cache
cacheDir = '/vol/cache/' + env.JOB_NAME.replaceAll('%', '_')

// copy data to master cache
def scpToMaster(os, from, to) {
    if (os == 'linux' || os == 'mac') {
        sh "scp '${from}' '${jenkinsMaster}:${cacheDir}/${to}'"
    }
    else if (os == 'windows') {
        bat "scp -F c:/Users/jenkins/ssh_config \"${from}\" \"${jenkinsMaster}:${cacheDir}/${to}\""
    }
}

// copy data from master cache
def scpFromMaster(os, from, to) {
    if (os == 'linux' || os == 'mac') {
        sh "scp '${jenkinsMaster}:${cacheDir}/${from}' '${to}'"
    }
    else if (os == 'windows') {
        bat "scp -F c:/Users/jenkins/ssh_config \"${jenkinsMaster}:${cacheDir}/${from}\" \"${to}\""
    }
}

// -----------------------------------------------------------------------------
// --SECTION--                                                       SCRIPTS SCM
// -----------------------------------------------------------------------------

def checkoutCommunity() {
    if (cleanBuild) {
        deleteDir()
    }

    retry(3) {
        try {
            checkout scm
            sh 'git clean -f -d -x'
        }
        // catch (hudson.AbortException ae) {
        //     throw ae
        // }
        catch (exc) {
            echo "GITHUB checkout failed, retrying in 5min"
            echo exc.toString()
            sleep 300
        }
    }
}

def checkoutEnterprise() {
    try {
        echo "Trying enterprise branch ${env.BRANCH_NAME}"

        checkout(
            changelog: false,
            poll: false,
            scm: [
                $class: 'GitSCM',
                branches: [[name: "*/${env.BRANCH_NAME}"]],
                doGenerateSubmoduleConfigurations: false,
                extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: 'enterprise']],
                submoduleCfg: [],
                userRemoteConfigs: [[credentialsId: credentials, url: enterpriseRepo]]])
    }
    catch (exc) {
        echo "Failed ${env.BRANCH_NAME}, trying enterprise branch devel"

        checkout(
            changelog: false,
            poll: false,
            scm: [
                $class: 'GitSCM',
                branches: [[name: "*/devel"]],
                doGenerateSubmoduleConfigurations: false,
                extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: 'enterprise']],
                submoduleCfg: [],
                userRemoteConfigs: [[credentialsId: credentials, url: enterpriseRepo]]])
    }

    sh 'cd enterprise && git clean -f -d -x'
}

def checkoutResilience() {
    checkout(
        changelog: false,
        poll: false,
        scm: [
            $class: 'GitSCM',
            branches: [[name: "*/master"]],
            doGenerateSubmoduleConfigurations: false,
            extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: 'resilience']],
            submoduleCfg: [],
            userRemoteConfigs: [[credentialsId: credentials, url: resilienceRepo]]])

    sh 'cd resilience && git clean -f -d -x'
}

def checkCommitMessages() {
    def changeLogSets = currentBuild.changeSets
    def seenCommit = false
    def skip = false

    for (int i = 0; i < changeLogSets.size(); i++) {
        def entries = changeLogSets[i].items

        for (int j = 0; j < entries.length; j++) {
            seenCommit = true

            def entry = entries[j]

            def author = entry.author
            def commitId = entry.commitId
            def msg = entry.msg
            def timestamp = new Date(entry.timestamp)

            echo msg

            if (msg ==~ /(?i).*\[ci:[^\]]*clean[ \]].*/) {
                echo "using clean build because message contained 'clean'"
                cleanBuild = true
            }

            if (msg ==~ /(?i).*\[ci:[^\]]*skip[ \]].*/) {
                echo "skipping everything because message contained 'skip'"
                skip = true
            }

            def files = new ArrayList(entry.affectedFiles)

            for (int k = 0; k < files.size(); k++) {
                def file = files[k]
                def editType = file.editType.name
                def path = file.path

                echo "File " + file + ", path " + path
            }
        }
    }

    if (skip) {
        useLinux = false
        useMac = false
        useWindows = false
        buildExecutable = false
        useCommunity = false
        useEnterprise = false
        runJslint = false
        runResilience = false
        runTests = false
    }
    else if (seenCommit) {
        if (env.BRANCH_NAME == "devel" || env.BRANCH_NAME == "3.2") {
            useLinux = true
            useMac = true
            useWindows = true
            buildExecutable = true
            useCommunity = true
            useEnterprise = true
            runJslint = true
            runResilience = true
            runTests = true
        }
        else if (env.BRANCH_NAME =~ /^PR-/) {
            useLinux = true
            useMac = true
            useWindows = true
            buildExecutable = true
            useCommunity = true
            useEnterprise = true
            runJslint = true
            runResilience = true
            runTests = true
        }
        else {
            useLinux = true
            useMac = true
            useWindows = true
            buildExecutable = true
            useCommunity = true
            useEnterprise = true
            runJslint = true
            runResilience = false
            runTests = false

            restrictions = [
                "build-enterprise-linux",
                "build-community-mac",
                "build-community-windows",
                "test-cluster-enterprise-rocksdb-linux",
                "test-singleserver-community-mmfiles-mac",
                "test-singleserver-community-rocksdb-windows"
            ]
        }
    }

    echo """BRANCH_NAME: ${env.BRANCH_NAME}
CHANGE_ID: ${env.CHANGE_ID}
CHANGE_TARGET: ${env.CHANGE_TARGET}
JOB_NAME: ${env.JOB_NAME}

Linux: ${useLinux}
Mac: ${useMac}
Windows: ${useWindows}
Build: ${buildExecutable}
Clean Build: ${cleanBuild}
Full Parallel: ${fullParallel}
Building Community: ${useCommunity}
Building Enterprise: ${useEnterprise}
Running Jslint: ${runJslint}
Running Resilience: ${runResilience}
Running Tests: ${runTests}"""
}

// -----------------------------------------------------------------------------
// --SECTION--                                                     SCRIPTS STASH
// -----------------------------------------------------------------------------

def stashSourceCode() {
    sh 'rm -f source.*'
    sh 'find -L . -type l -delete'
    sh 'zip -r -1 -x "*tmp" -x ".git" -y -q source.zip *'

    lock("${env.BRANCH_NAME}-cache") {
        sh 'mkdir -p ' + cacheDir
        sh "mv -f source.zip ${cacheDir}/source.zip"
    }
}

def unstashSourceCode(os) {
    deleteDir()

    lock("${env.BRANCH_NAME}-cache") {
        scpFromMaster(os, 'source.zip', 'source.zip')
    }

    if (os == 'linux' || os == 'mac') {
        sh 'unzip -o -q source.zip'
        sh 'rm -f source.zip'
    }
    else if (os == 'windows') {
        bat 'c:\\cmake\\bin\\cmake -E tar xf source.zip'
        bat 'del /q /f source.zip'
    }
}

def stashBuild(edition, os) {
    def name = "build-${edition}-${os}.zip"

    if (os == 'linux' || os == 'mac') {
        sh "rm -f ${name}"
        sh "zip -r -1 -y -q ${name} build-${edition}"
    }
    else if (os == 'windows') {
        bat "del /F /Q ${name}"
        bat "c:\\cmake\\bin\\cmake -E tar cf ${name} build"
    }

    lock("${env.BRANCH_NAME}-cache") {
        scpToMaster(os, name, name)
    }
}

def unstashBuild(edition, os) {
    def name = "build-${edition}-${os}.zip"

    lock("${env.BRANCH_NAME}-cache") {
        scpFromMaster(os, name, name)
    }

    if (os == 'linux' || os == 'mac') {
        sh "unzip -o -q ${name}"
        sh "rm -f ${name}"
    }
    else if (os == 'windows') {
        bat "c:\\cmake\\bin\\cmake -E tar xf ${name}"
        bat "del /F /Q ${name}"
    }
}

def stashBinaries(edition, os) {
    def name = "binaries-${edition}-${os}.zip"
    def dirs = 'build etc Installation/Pipeline js scripts UnitTests utils resilience'

    if (edition == 'enterprise') {
        dirs = "${dirs} enterprise/js"
    }

    if (os == 'linux' || os == 'mac') {
        sh "zip -r -1 -y -q ${name} ${dirs}"
    }
    else if (os == 'windows') {
        bat "c:\\cmake\\bin\\cmake -E tar cf ${name} ${dirs}"
    }

    lock("${env.BRANCH_NAME}-cache") {
        scpToMaster(os, name, name)
    }
}

def unstashBinaries(edition, os) {
    def name = "binaries-${edition}-${os}.zip"

    deleteDir()

    lock("${env.BRANCH_NAME}-cache") {
        scpFromMaster(os, name, name)
    }

    if (os == 'linux' || os == 'mac') {
        sh "unzip -o -q  ${name}"
        sh "rm -f ${name}"
    }
    else if (os == 'windows') {
        bat "c:\\cmake\\bin\\cmake -E tar xf ${name}"
        bat "del /F /Q ${name}"
    }
}

// -----------------------------------------------------------------------------
// --SECTION--                                                         VARIABLES
// -----------------------------------------------------------------------------

buildJenkins = [
    "linux": "linux && build",
    "mac" : "mac",
    "windows": "windows"
]

buildsSuccess = [:]
allBuildsSuccessful = true

jslintSuccessful = true

testJenkins = [
    "linux": "linux && tests",
    "mac" : "mac",
    "windows": "windows"
]

testsSuccess = [:]
allTestsSuccessful = true

// -----------------------------------------------------------------------------
// --SECTION--                                                    SCRIPTS JSLINT
// -----------------------------------------------------------------------------

def jslint() {
    try {
        sh './Installation/Pipeline/test_jslint.sh'
    }
    // catch (hudson.AbortException ae) {
    //     throw ae
    // }
    catch (exc) {
        jslintSuccessful = false
        throw exc
    }
}

def jslintStep(edition) {
    def os = 'linux'

    return {
        node(os) {
            echo "Running jslint test"

            unstashBinaries(edition, os)
            jslint()
        }
    }
}

// -----------------------------------------------------------------------------
// --SECTION--                                                     SCRIPTS TESTS
// -----------------------------------------------------------------------------

def testEdition(edition, os, mode, engine) {
    def arch = "LOG_test_${mode}_${edition}_${engine}_${os}"

    try {
        try {
            if (os == 'linux') {
                sh "./Installation/Pipeline/linux/test_${mode}_${edition}_${engine}_${os}.sh 10"
            }
            else if (os == 'mac') {
                sh "./Installation/Pipeline/mac/test_${mode}_${edition}_${engine}_${os}.sh 5"
            }
            else if (os == 'windows') {
                powershell ". .\\Installation\\Pipeline\\windows\\test_${mode}_${edition}_${engine}_${os}.ps1"
            }
        }
        catch (exc) {
            if (os == 'linux' || os == 'mac') {
                sh "for i in build core* tmp; do test -e \$i && mv \$i ${arch} || true; done"
            }

            throw exc
        }
        finally {
            if (os == 'linux' || os == 'mac') {
                sh "rm -rf ${arch}"
                sh "mkdir -p ${arch}"
                sh "find log-output -name 'FAILED_*' -exec cp '{}' . ';'"
                sh "for i in logs log-output core*; do test -e \$i && mv \$i ${arch} || true; done"
            }
        }
    }
    // catch (hudson.AbortException ae) {
    //     throw ae
    // }
    finally {
        archiveArtifacts allowEmptyArchive: true,
                         artifacts: "${arch}/**",
                         defaultExcludes: false

        archiveArtifacts allowEmptyArchive: true,
                         artifacts: "FAILED_*",
                         defaultExcludes: false
    }
}

def testCheck(edition, os, mode, engine, full) {
    def name = "${edition}-${os}"

    if (! runTests) {
        return false
    }

    if (os == 'linux' && ! useLinux) {
        return false
    }

    if (os == 'mac' && ! useMac) {
        return false
    }

    if (os == 'windows' && ! useWindows) {
        return false
    }

    if (edition == 'enterprise' && ! useEnterprise) {
        return false
    }

    if (edition == 'community' && ! useCommunity) {
        return false
    }

    return true
}

def testStep(edition, os, mode, engine) {
    return {
        node(testJenkins[os]) {
            def buildName = "${edition}-${os}"

            if (buildsSuccess[buildName]) {
                def name = "${edition}-${os}-${mode}-${engine}"

                try {
                    unstashBinaries(edition, os)
                    testEdition(edition, os, mode, engine)
                    testsSuccess[name] = true
                }
                // catch (hudson.AbortException ae) {
                //     throw ae
                // }
                catch (exc) {
                    echo exc.toString()
                    testsSuccess[name] = false
                    allTestsSuccessful = false
                    throw exc
                }
            }
            else {
                error "build failed, cannot test"
            }
        }
    }
}

def testStepParallel(editionList, osList, modeList) {
    def branches = [:]
    def full = false

    for (edition in editionList) {
        for (os in osList) {
            for (mode in modeList) {
                for (engine in ['mmfiles', 'rocksdb']) {
                    if (testCheck(edition, os, mode, engine, full)) {
                        def name = "test-${mode}-${edition}-${engine}-${os}";

                        branches[name] = testStep(edition, os, mode, engine)
                    }
                }
            }
        }
    }

    if (runJslint && osList.contains('linux') && useLinux && useCommunity) {
        branches['jslint'] = jslintStep('community')
    }

    if (branches.size() > 1) {
        parallel branches
    }
    else if (branches.size() == 1) {
        branches.values()[0]()
    }
}

// -----------------------------------------------------------------------------
// --SECTION--                                                SCRIPTS RESILIENCE
// -----------------------------------------------------------------------------

resiliencesSuccess = [:]
allResiliencesSuccessful = true

def testResilience(os, engine, foxx) {
    withEnv(['LOG_COMMUNICATION=debug', 'LOG_REQUESTS=trace', 'LOG_AGENCY=trace']) {
        if (os == 'linux') {
            sh "./Installation/Pipeline/linux/test_resilience_${foxx}_${engine}_${os}.sh"
        }
        else if (os == 'mac') {
            sh "./Installation/Pipeline/mac/test_resilience_${foxx}_${engine}_${os}.sh"
        }
        else if (os == 'windows') {
            powershell ".\\Installation\\Pipeline\\test_resilience_${foxx}_${engine}_${os}.ps1"
        }
    }
}

def testResilienceCheck(os, engine, foxx, full) {
    def name = "community-${os}"

    if (! runResilience) {
        return false
    }

    if (os == 'linux' && ! useLinux) {
        return false
    }

    if (os == 'mac' && ! useMac) {
        return false
    }

    if (os == 'windows' && ! useWindows) {
        return false
    }

    if (! useCommunity) {
        return false
    }

    return true
}

def testResilienceName(os, engine, foxx, full) {
    def name = "test-resilience-${foxx}-${engine}-${os}";

    if (! testResilienceCheck(os, engine, foxx, full)) {
        name = "DISABLED-${name}"
    }

    return name 
}

def testResilienceStep(os, engine, foxx) {
    return {
        node(testJenkins[os]) {
            def edition = "community"
            def buildName = "${edition}-${os}"

            if (buildsSuccess[buildName]) {
                def name = "${os}-${engine}-${foxx}"
                def arch = "LOG_resilience_${foxx}_${engine}_${os}"

                try {
                    try {
                        unstashBinaries(edition, os)
                        testResilience(os, engine, foxx)
                    }
                    catch (exc) {
                        if (os == 'linux' || os == 'mac') {
                            sh "for i in build core* tmp; do test -e \$i && mv \$i ${arch} || true; done"
                        }

                        throw exc
                    }
                    finally {
                        if (os == 'linux' || os == 'mac') {
                            sh "rm -rf ${arch}"
                            sh "mkdir -p ${arch}"
                            sh "for i in log-output resilience/core*; do test -e \$i && mv \$i ${arch}; done"
                        }
                        else if (os == 'windows') {
                            bat "del /F /Q ${arch}"
                            powershell "New-Item -ItemType Directory -Force -Path ${arch}"
                            bat "move log-output ${arch}"
                        }
                        
                    }
                }
                // catch (hudson.AbortException ae) {
                //     throw ae
                // }
                catch (exc) {
                    resiliencesSuccess[name] = false
                    allResiliencesSuccessful = false

                    throw exc
                }
                finally {
                    archiveArtifacts allowEmptyArchive: true,
                                     artifacts: "${arch}/**",
                                     defaultExcludes: false
                }
            }
            else {
                error "build failed, cannot test"
            }
        }
    }
}

def testResilienceParallel(osList) {
    def branches = [:]
    def full = false

    for (foxx in ['foxx', 'nofoxx']) {
        for (os in osList) {
            for (engine in ['mmfiles', 'rocksdb']) {
                if (testResilienceCheck(os, engine, foxx, full)) {
                    def name = testResilienceName(os, engine, foxx, full)

                    branches[name] = testResilienceStep(os, engine, foxx)
                }
            }
        }
    }

    if (branches.size() > 1) {
        parallel branches
    }
    else if (branches.size() == 1) {
        branches.values()[0]()
    }
}

// -----------------------------------------------------------------------------
// --SECTION--                                                     SCRIPTS BUILD
// -----------------------------------------------------------------------------

def buildEdition(edition, os) {
    if (! cleanBuild) {
        try {
            unstashBuild(edition, os)
        }
        // catch (hudson.AbortException ae) {
        //     throw ae
        // }
        catch (exc) {
            echo "no stashed build environment, starting clean build"
        }
    }

    def arch = "LOG_build_${edition}_${os}"

    try {
        try {
            if (os == 'linux') {
                sh "./Installation/Pipeline/linux/build_${edition}_${os}.sh 64"
            }
            else if (os == 'mac') {
                sh "./Installation/Pipeline/mac/build_${edition}_${os}.sh 20"
            }
            else if (os == 'windows') {
                powershell ". .\\Installation\\Pipeline\\windows\\build_${edition}_${os}.ps1"
            }
        }
        finally {
            if (os == 'linux' || os == 'mac') {
                sh "rm -rf ${arch}"
                sh "mkdir -p ${arch}"
                sh "for i in log-output; do test -e \$i && mv \$i ${arch} || true; done"
            }
            else if (os == 'windows') {
                bat "del /F /Q ${arch}"
                powershell "New-Item -ItemType Directory -Force -Path ${arch}"
            }
        }
    }
    finally {
        stashBuild(edition, os)

        archiveArtifacts allowEmptyArchive: true,
                         artifacts: "${arch}/**",
                         defaultExcludes: false
    }
}

def buildStepCheck(edition, os, full) {
    if (os == 'linux' && ! useLinux) {
        return false
    }

    if (os == 'mac' && ! useMac) {
        return false
    }

    if (os == 'windows' && ! useWindows) {
        return false
    }

    if (edition == 'enterprise' && ! useEnterprise) {
        return false
    }

    if (edition == 'community' && ! useCommunity) {
        return false
    }

    return true
}

def buildStep(edition, os) {
    return {
        lock("${env.BRANCH_NAME}-build-${edition}-${os}") {
            node(buildJenkins[os]) {
                def name = "${edition}-${os}"

                try {
                    unstashSourceCode(os)
                    buildEdition(edition, os)
                    stashBinaries(edition, os)
                    buildsSuccess[name] = true
                }
                // catch (hudson.AbortException ae) {
                //     throw ae
                // }
                catch (exc) {
                    buildsSuccess[name] = false
                    allBuildsSuccessful = false
                    throw exc
                }
            }
        }
    }
}

def buildStepParallel(osList) {
    def branches = [:]
    def full = false

    for (edition in ['community', 'enterprise']) {
        for (os in osList) {
            if (buildStepCheck(edition, os, full)) {
                branches["build-${edition}-${os}"] = buildStep(edition, os)
            }
        }
    }

    if (branches.size() > 1) {
        parallel branches
    }
    else if (branches.size() == 1) {
        branches.values()[0]()
    }
}

// -----------------------------------------------------------------------------
// --SECTION--                                                          PIPELINE
// -----------------------------------------------------------------------------

def runStage(stage) {
    try {
        stage()
    }
    // catch (hudson.AbortException ae) {
    //     echo exc.toString()
    //     throw ae
    // }
    catch (exc) {
        echo exc.toString()
    }
}

stage('checkout') {
    node('master') {
        checkoutCommunity()
        checkCommitMessages()
        checkoutEnterprise()
        checkoutResilience()
        stashSourceCode()
    }
}

if (buildExecutable) {
    runStage {
        stage('build') {
            if (fullParallel) {
                buildStepParallel(['linux', 'mac', 'windows'])
            }
            else {
                buildStepParallel(['linux'])
            }
        }
    }
}

runStage {
    stage('tests') {
        if (fullParallel) {
            testStepParallel(['community', 'enterprise'], ['linux', 'mac', 'windows'], ['cluster', 'singleserver'])
            testResilienceParallel(['linux', 'mac', 'windows'])
        }
        else {
            testStepParallel(['community', 'enterprise'], ['linux'], ['cluster', 'singleserver'])
        }
    }
}

if (! fullParallel) {
    runStage {
        stage('build mac') {
            if (allBuildsSuccessful) {
                buildStepParallel(['mac'])
            }
        }
    }

    runStage {
        stage('tests mac') {
            if (allTestsSuccessful || ! skipTestsOnError) {
                testStepParallel(['community', 'enterprise'], ['mac'], ['cluster', 'singleserver'])
            }
        }
    }

    runStage {
        stage('build windows') {
            if (allBuildsSuccessful) {
                buildStepParallel(['windows'])
            }
        }
    }

    runStage {
        stage('tests windows') {
            if (allTestsSuccessful || ! skipTestsOnError) {
                testStepParallel(['community', 'enterprise'], ['windows'], ['cluster', 'singleserver'])
            }
        }
    }

    runStage {
        stage('resilience') {
            if (allTestsSuccessful) {
                testResilienceParallel(['linux', 'mac', 'windows'])
            }
        }
    }
}

stage('result') {
    node('master') {
        def result = ""

        if (!jslintSuccessful) {
            result += "JSLINT failed\n"
        }

        for (kv in buildsSuccess) {
            result += "BUILD ${kv.key}: ${kv.value}\n"
        }

        for (kv in testsSuccess) {
            result += "TEST ${kv.key}: ${kv.value}\n"
        }

        for (kv in resiliencesSuccess) {
            result += "RESILIENCE ${kv.key}: ${kv.value}\n"
        }

        if (result == "") {
           result = "All tests passed!"
        }

        echo result

        if (! (allBuildsSuccessful
            && allTestsSuccessful
            && allResiliencesSuccessful
            && jslintSuccessful)) {
            error "run failed"
        }
    }
}