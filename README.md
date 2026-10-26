# Elm-gRPC

gRPC-Web Implementation for the Elm programming language.

Designed for [protoc-gen-elm](https://github.com/anmolitor/protoc-gen-elm) code generation.

Important note: Thanks to Martin Rosenberg for his [elm-grpc](https://package.elm-lang.org/packages/rosenbergm/elm-grpc/latest/) package which this package builds upon. I felt like I wanted a different API for protoc-gen-elm than what he currently has and wanted freedom to iterate quickly and show my API to other developers.
We can merge the packages later!

## Limitations

Unary and server-streaming requests are supported. Read a server stream with `Grpc.Streaming`. The response is
received in full, since Elm hands over a response body only once it is complete, and its messages are then decoded
one at a time as they are read. It suits finite streams, not ones that stay open.
As far as I am aware, grpc-web as a whole is blocked on client-side streaming/bidirectional streaming due to missing browser support.

## Shoutouts

- Thanks to Erik Timmers for the incredible [elm-protocol-buffers](https://package.elm-lang.org/packages/eriktim/elm-protocol-buffers/latest/) package. 

## Resources

- gRPC: https://grpc.io/
- gRPC-Web: https://github.com/grpc/grpc-web