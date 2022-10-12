FROM ghcr.io/graalvm/graalvm-ce:latest as build-image

RUN gu install native-image
RUN microdnf install yum
ENV LC_ALL C
RUN yum -y install scala
RUN yum -y install unzip zip
RUN curl -s "https://get.sdkman.io" | bash
RUN echo ". $HOME/.sdkman/bin/sdkman-init.sh; sdk install sbt" | bash

WORKDIR /work
COPY ./ ./

RUN $HOME/.sdkman/candidates/sbt/current/bin/sbt nativeImage
RUN mv ./target/native-image/bootstrap .
RUN chmod +x bootstrap

FROM public.ecr.aws/lambda/provided:al2

COPY --from=build-image /work/bootstrap /var/runtime/

CMD ["dummyHandler"]
