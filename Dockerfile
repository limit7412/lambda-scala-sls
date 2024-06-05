FROM virtuslab/scala-cli:latest as build-image

WORKDIR /work
COPY ./ ./

RUN scala-cli clean .
RUN scala-cli config power true
# target GraalVM
RUN scala-cli --power package --native-image -o bootstrap .
# target Scala Native
# RUN scala-cli --power package --native -o bootstrap .
RUN chmod +x bootstrap

FROM public.ecr.aws/lambda/provided:al2

COPY --from=build-image /work/bootstrap /var/runtime/

CMD ["dummyHandler"]