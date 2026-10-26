module Grpc.Internal exposing
    ( Rpc(..)
    , ResponseDecoder, singleMessageDecoder
    , ServerStream(..), serverStreamDecoder
    )

{-| Internals that are intended to be used from code generators.


# Rpc representation

@docs Rpc


# Response decoding

@docs ResponseDecoder, singleMessageDecoder


# Server streaming

@docs ServerStream, serverStreamDecoder

-}

import Array exposing (Array)
import Bytes exposing (Bytes)
import Protobuf.Decode exposing (Decoder)
import Protobuf.Encode exposing (Encoder)


{-| Turn the messages of a response into its value, or `Nothing` if they don't decode.
-}
type alias ResponseDecoder res =
    Array Bytes -> Maybe res


{-| Given the following proto file

    """
    syntax = "proto3";

    package helloworld;

    service Greeter {
      rpc SayHello (HelloRequest) returns (HelloReply) {}
    }

    message HelloRequest {
      string name = 1;
    }

    message HelloReply {
      string message = 1;
    }
    """

the corresponding Rpc instance would be

    Rpc
        { service = "Greeter"
        , package = "helloworld"
        , rpcName = "SayHello"
        , encoder = helloRequestEncoder
        , decoder = Grpc.Internal.singleMessageDecoder helloReplyDecoder
        }

where `helloRequestEncoder` and `helloReplyDecoder` are Encoders/Decoders built with `elm-protocol-buffers`.

-}
type Rpc req res
    = Rpc
        { service : String
        , package : String
        , rpcName : String
        , encoder : req -> Encoder
        , decoder : ResponseDecoder res
        }


{-| Decode the response of a unary rpc, which carries one message.
-}
singleMessageDecoder : Decoder res -> ResponseDecoder res
singleMessageDecoder decoder =
    Array.get 0
        >> Maybe.andThen (Protobuf.Decode.decode decoder)


{-| The messages a server-streaming rpc responded with, each still undecoded. Code generators give a server-streaming
rpc the response type `ServerStream res`, and `Grpc.Streaming.fromRequest` takes a request for one.
-}
type ServerStream res
    = ServerStream (Array Bytes) (Decoder res)


{-| Wrap the messages of a server-streaming response in a `ServerStream` without decoding them. This never fails;
`Grpc.Streaming` decodes each message when it reads it.
-}
serverStreamDecoder : Decoder res -> ResponseDecoder (ServerStream res)
serverStreamDecoder decoder frames =
    Just (ServerStream frames decoder)
