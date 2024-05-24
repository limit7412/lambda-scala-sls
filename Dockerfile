FROM sbtscala/scala-sbt:eclipse-temurin-jammy-21.0.2_13_1.10.0_3.3.3 as build-image

WORKDIR /work
COPY ./ ./

RUN apt -y clean && apt -y update
RUN apt -y install clang
RUN apt -y install libcurl4-openssl-dev
RUN apt -y install libidn2-0-dev
RUN apt -y install libkrb5-dev
RUN apt -y install build-essential

ENV LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"

RUN sbt nativeLink
RUN mv ./target/scala-3.3.3/lambda-scala-sls ./bootstrap
RUN chmod +x bootstrap

FROM public.ecr.aws/lambda/provided:latest

COPY --from=build-image /work/bootstrap /var/runtime/

CMD ["dummyHandler"]
