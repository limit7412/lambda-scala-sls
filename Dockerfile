FROM hseeberger/scala-sbt:graalvm-ce-21.1.0-java11_1.5.4_2.13.6 as build-image

WORKDIR /work
COPY ./ ./

RUN sbt nativeImage
RUN mv ./target/native-image/bootstrap .
RUN chmod +x bootstrap

FROM public.ecr.aws/lambda/provided:al2

COPY --from=build-image /work/bootstrap /var/runtime/

CMD ["dummyHandler"]
