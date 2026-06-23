# Jenkins LTS + the Docker CLI / Compose plugin so pipeline steps can drive the
# host Docker daemon (Docker-out-of-Docker via the mounted /var/run/docker.sock).
# Plugins + the whole job config are baked/declared so the controller comes up
# fully configured with NO manual setup-wizard clicks (JCasC + Job DSL).
FROM jenkins/jenkins:lts-jdk17

USER root

# Docker CLI + compose-plugin (talks to the host daemon over the mounted socket),
# plus git/python3 used by the pipeline shell steps.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg git python3 \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        docker-ce-cli docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# Install plugins at build time (offline-resolved with deps).
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Skip the setup wizard and let Job DSL run without per-script approval (this is a
# single-tenant local CI box, not a multi-user Jenkins).
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Djavaposse.jobdsl.plugin.GlobalJobDslSecurityConfiguration.useScriptSecurity=false"
ENV CASC_JENKINS_CONFIG=/var/jenkins_conf/casc.yaml

# We run the container as root so it can read the host docker.sock and the
# bind-mounted project tree (owned by the host user); run_ci.sh chowns its own
# artifacts back to HOST_UID:HOST_GID at the end.
USER root
