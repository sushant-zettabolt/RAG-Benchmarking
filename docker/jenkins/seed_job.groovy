// Job DSL seed for the ZenDNN regression watch, applied by JCasC at boot
// (casc.yaml -> jobs: -> file). Creates one cron pipeline job that runs the CI.
pipelineJob('zendnn-regression-watch') {
    description('Cron-scheduled fresh-pull rebuild of llama.cpp + ZenDNN, standard RAG eval, then a strictly ZenDNN->ZenDNN-across-time comparison (degrade / neutral / speedup). Testing cron is every 30 min; switch the trigger to weekly for production.')
    keepDependencies(false)
    parameters {
        booleanParam('FRESH_BUILD', true, 'Rebuild baseline + ZenDNN images --no-cache (fresh pull of latest llama.cpp HEAD + public ZenDNN) before the eval. Scheduled runs leave this true; turn it off for a quick wiring test.')
    }
    logRotator {
        numToKeep(60)
        artifactNumToKeep(60)
    }
    triggers {
        // ── TESTING cadence: every 30 minutes. For the real weekly cadence,
        //    replace with:  cron('H H(0-6) * * 1')   (~weekly, early Monday).
        cron('H/30 * * * *')
    }
    definition {
        cps {
            sandbox(true)
            script('''
// Never run two cycles at once: a fresh-pull rebuild + eval can outlast the
// 30-min test cron, and concurrent runs would fight over the benchmark containers.
properties([disableConcurrentBuilds()])
node {
    def proj = env.PROJECT_DIR ?: '/home/zettabolt/mkumar/sushant/RAG_testing/rag_pipeline_bench'
    timestamps {
        dir(proj) {
            stage('Run CI (fresh-pull rebuild + eval + compare)') {
                sh "FRESH_BUILD=${params.FRESH_BUILD} bash ci/run_ci.sh"
            }
            stage('Publish verdict') {
                def v = readFile('ci/runs/latest/verdict.txt').trim()
                echo "ZenDNN regression verdict: ${v}"
                currentBuild.description = v
                archiveArtifacts artifacts: 'ci/runs/latest/**', allowEmptyArchive: true
                if (v.startsWith('DEGRADE')) {
                    currentBuild.result = 'UNSTABLE'
                }
            }
        }
    }
}
'''.stripIndent())
        }
    }
}
