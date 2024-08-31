FROM ubuntu:latest
LABEL authors="i.akhaltsev"

ENTRYPOINT ["top", "-b"]