#!/usr/bin/groovy

/*
*
* This script will create a tag out of master branch with name specified in `releaseBranch` parameter variable.
* Checks for upstream branch with same name; then stops execution with and exception if same branch found in upstream.
*
* Parameters:
*   Name:   gitCredentialId
*      Type:   environment variable or jenkins parameter
*      Description:    contains github username and password for the user to be used
*   Name:   releaseBranch
*      Type:   jenkins parameter
*      Description:    Name of the branch to create
*
* Author: Rajesh Rajendran<rjshrjndrn@gmail.com>
*
* This script uses curl and jq from the machine.
*
*/

node {
    // Creating color code strings
    String ANSI_GREEN = "\u001B[32m"
    String ANSI_NORMAL = "\u001B[0m"
    String ANSI_BOLD = "\u001B[1m"
    String ANSI_RED = "\u001B[31m"
    def gitCredentialId = params.gitCredentialId ?: 'githubPassword'
    try{

        // Checking first build and creating parameters
        if (params.size() == 0){
            properties([[$class: 'RebuildSettings', autoRebuild: false, rebuildDisabled: false],
                        parameters([string(defaultValue: '',
                        description: '<font color=teal size=2>Release Branch name to STOP</font>',
                        name: 'releaseBranch', trim: true)])])
            ansiColor('xterm') {
                println (ANSI_BOLD + ANSI_GREEN + '''\
                        First run of the job. Parameters created. Stopping the current build.
                        Please trigger new build and provide parameters if required.
                        '''.stripIndent().replace("\n"," ") + ANSI_NORMAL)
            }
        return
        }

        // Make sure prerequisites are met
        // If releaseBranch variable not set
        if (params.releaseBranch == ''){
            println(ANSI_BOLD + ANSI_RED + 'Release branch name not set' + ANSI_NORMAL)
            error 'Release branch name not set'
        } 
        // Checking out public repo from where the branch should be created
        stage('Checking out branch'){
            // Cleaning workspace
            cleanWs()
            checkout scm
            ansiColor('xterm'){
                if( sh(
                script:  "git ls-remote --exit-code --heads origin ${params.releaseBranch}",
                returnStatus: true
                ) != 0) {
                    println(ANSI_BOLD + ANSI_RED + 'Release branch does not exist' + ANSI_NORMAL)
                    error 'Branch not exist'
                }
            }
        }
        stage("Creating PR") {
        // api.github.com/repos/rjshrjndrn/sunbird-devops/pulls' -d \
        // '{"title": "Automatic PR from Sunbird Bot", "head": "release-test", "base": "master"}'

            withCredentials([usernamePassword(credentialsId: "${gitCredentialId}",
            passwordVariable: 'gitPassword', usernameVariable: 'gitUser')]) {
                // Getting git remote api url
                origin = "https://${gitUser}:${gitPassword}@api.github.com/repos/"+gitUser+"/"+sh(
                script: 'git config --get remote.origin.url',
                returnStdout: true
                ).trim().split('/')[-1].split('\\.')[0]+"/pulls"
                def prRequest = sh (
                   script: """curl -s -w %{http_code} -XPOST ${origin} -d '{"title": "Automatic PR From Sunbird Bot", "head": "${params.releaseBranch}", "base":"master"}' -o /tmp/output""",
                   returnStdout: true
                ).trim()
                // Cheking PR is success
                if(prRequest != '201'){
                    // If PR exists
                    if(prRequest == '422' && sh(
                        script: "cat /tmp/output | jq '.errors[0].code'",
                        returnStdout: true
                        ).trim() == "already_exists") {
                        ansiColor('xterm'){
                            println(ANSI_BOLD + ANSI_GREEN +
                            'GitHub PR found\nPR: '+ANSI_NORMAL+sh(
                            script: 'git config --get remote.origin.url',
                            returnStdout: true
                            ).trim().split('\\.git')[0]+'/pulls')
                        }
                    }
                    // Unknown error
                    else {
                        error 'Could not raise the PR'
                    }
                }
            }
        }
        stage("Merging master with ${params.releaseBranch}"){

            if( sh (
                script: " git checkout origin/master && git merge origin/${params.releaseBranch} ",
                returnStatus: true
                ) != 0){
                    ansiColor('xterm'){
                        println(ANSI_BOLD + ANSI_RED +
                        "Merge Conflict\nPR Raised\nPlease fix the Conflicts and run the job again\nPR: "
                        +ANSI_NORMAL+sh(
                        script: 'git config --get remote.origin.url',
                        returnStdout: true
                        ).trim().split('\\.git')[0]+'/pulls')
                    }
                    error 'Merge Conflict'
            }
        }
        stage('pushing tag to upstream'){
            // Using withCredentials as gitpublish plugin is not yet ported for pipelines
            // Defining credentialsId for default value passed from Parameter or environment value.
            // gitCredentialId is username and password type
            withCredentials([usernamePassword(credentialsId: "${gitCredentialId}",
            passwordVariable: 'gitPassword', usernameVariable: 'gitUser')]) {

                // Getting git remote url
                origin = "https://${gitUser}:${gitPassword}@"+sh (
                script: 'git config --get remote.origin.url',
                returnStdout: true
                ).trim().split('https://')[1]
                echo "Git Hash: ${origin}"
                // Checks whether remtoe branch is present
                // Stdouts 1 if true
                remoteBranch = 
                ansiColor('xterm'){
                    // If remote tag exists
                    if( sh(script: "git ls-remote --tags ${origin} ${params.releaseBranch}", returnStatus: true) == 0 ) {
                        println(ANSI_BOLD + ANSI_RED + "Upstream has tag with same name: ${params.releaseBranch}" + ANSI_NORMAL)
                        error 'remote tag found with same name'
                    }
                }
                // Pushing tag
                sh("git push ${origin} HEAD:tags/${params.releaseBranch}")
                // Deleting branch
                sh("git push ${origin} :heads/${params.releaseBranch}")
            }
        }
    }
    catch(org.jenkinsci.plugins.credentialsbinding.impl.CredentialNotFoundException e){
        ansiColor('xterm'){
            println(ANSI_BOLD + ANSI_RED + '''\
            either github credentialsId is not set or value is not correct. please set it as
            an environment variable. Derfault credentialsId name will be "githubPassword". The variable is supposed to contain a jenkins
            OcredentialsId which has github username, github password
            '''.stripIndent() + ANSI_NORMAL)
        error 'either gitCredentialId is not set or wrong value'
        }
    }
}
