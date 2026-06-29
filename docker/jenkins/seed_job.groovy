// Job DSL seed for the ZenDNN regression watch, applied by JCasC at boot
// (casc.yaml -> jobs: -> file). Creates one cron pipeline job that runs the CI.
pipelineJob('zendnn-regression-watch') {
    description('Cron-scheduled fresh-pull rebuild of llama.cpp + ZenDNN, standard RAG eval, then a strictly ZenDNN->ZenDNN-across-time comparison (degrade / neutral / speedup). Cron fires weekly (early Monday, hour 0-6, hashed minute).')
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
// Re-assert BOTH the concurrency rule and the cron on every run. `properties()`
// REPLACES the job's whole property set, so listing only disableConcurrentBuilds()
// here would wipe the cron trigger the Job DSL set above after the first build
// (a silent bug). Declaring the cron here too makes it self-healing — every build
// re-registers it. Keep this spec identical to the DSL `triggers{cron(...)}`.
//   weekly: fires early Monday (hour 0-6), minute+hour hashed from the job name.
properties([
    disableConcurrentBuilds(),
    pipelineTriggers([cron('H H(0-6) * * 1')])
])
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
