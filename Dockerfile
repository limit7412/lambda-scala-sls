FROM ghcr.io/graalvm/graalvm-ce:latest as build-image

RUN gu install native-image
RUN microdnf install yum
ENV LC_ALL C
RUN yum -y install scala
RUN yum -y install unzip zip
RUN curl -s "https://get.sdkman.io" | bash
RUN source "$HOME/.sdkman/bin/sdkman-init.sh"
RUN sdk install sbt

WORKDIR /work
COPY ./ ./

RUN sbt nativeImage
RUN mv ./target/native-image/bootstrap .
RUN chmod +x bootstrap

FROM public.ecr.aws/lambda/provided:al2

COPY --from=build-image /work/bootstrap /var/runtime/

CMD ["dummyHandler"]
