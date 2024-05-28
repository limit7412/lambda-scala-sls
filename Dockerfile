FROM virtuslab/scala-cli:latest as build-image

WORKDIR /work
COPY ./ ./

RUN scala-cli clean .
RUN scala-cli config power true
RUN scala-cli --power package  --native-image --graalvm-args='--static' --graalvm-args='--no-fallback' -o bootstrap .
# RUN scala-cli --power package --native-image --graalvm-args='--static' --graalvm-args='--no-fallback' -o bootstrap ex.scala
RUN chmod +x bootstrap

FROM public.ecr.aws/lambda/provided:al2

COPY --from=build-image /work/bootstrap /var/runtime/

CMD ["dummyHandler"]