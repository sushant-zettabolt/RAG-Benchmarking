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
        // ── Cadence: weekly. `H` hashes the exact minute + hour within the window
        //    so the (long, fresh-rebuild) build lands at a stable off-peak time
        //    early Monday (hour 0-6) rather than a thundering-herd midnight.
        cron('H H(0-6) * * 1')
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
