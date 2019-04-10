FROM centos:7

LABEL maintainer="Tobias Derksen <tobias.derksen@codecentric.de>"
LABEL description="Cluster Backups for OpenShift 3"

USER root

RUN yum -y install centos-release-openshift-origin311 epel-release && \
    yum -y install origin-clients jq openssl tar gzip shred && \
    rm -rf /var/cache/yum

RUN mkdir -p /backup /opt/backup/scripts /.kube && \
    touch /.kube/config && \
    chmod -R 755 /opt/backup && \
    chmod -R 766 /backup && \
    chmod -R  777 /.kube

WORKDIR /opt/backup
COPY export.sh /opt/backup/
COPY scripts/ /opt/backup/scripts/

CMD [ "/opt/backup/export.sh" ]
