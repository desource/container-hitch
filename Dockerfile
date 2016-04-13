FROM scratch

ADD bin/hitch      /bin/hitch

ENTRYPOINT [ "/bin/hitch" ]
