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
        // ── Cadence: every 2.5 hours. Cron can't step by 150 min in one line
        //    (2.5h doesn't divide 24h evenly), so two lines tile the day at exact
        //    2.5h spacing — 00:00,02:30,05:00,07:30,10:00,12:30,15:00,17:30,20:00,
        //    22:30 (the only short gap is the 22:30->00:00 wrap, 1.5h). For the
        //    real weekly cadence, replace with:  cron('H H(0-6) * * 1').
        cron('''0 0,5,10,15,20 * * *
30 2,7,12,17,22 * * *''')
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
    // All artifacts + history live here (repoint to reset history). Default: <proj>/ci.
    def artifactDir = env.CI_ARTIFACT_DIR ?: "${proj}/ci"
    timestamps {
        dir(proj) {
            stage('Run CI (fresh-pull rebuild + multi-model eval + compare)') {
                sh "FRESH_BUILD=${params.FRESH_BUILD} bash ci/run_ci.sh"
            }
        }
        stage('Publish verdict') {
            // Per-model summary, informational only — multi-model runs are NOT gated.
            def v = readFile("${artifactDir}/runs/latest/verdict.txt").trim()
            echo "ZenDNN regression (per-model): ${v}"
            currentBuild.description = v
            dir(artifactDir) {
                archiveArtifacts artifacts: 'runs/latest/**', allowEmptyArchive: true
            }
        }
    }
}
'''.stripIndent())
        }
    }
}
