module Grpc.Internal exposing
    ( Rpc(..)
    , ResponseDecoder, singleMessageDecoder, streamToListDecoder
    )

{-| Internals that are intended to be used from code generators.


# Rpc representation

@docs Rpc

-}

import Array exposing (Array)
import Bytes exposing (Bytes)
import Protobuf.Decode exposing (Decoder)
import Protobuf.Encode exposing (Encoder)


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
        , decoder = helloReplyDecoder
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


singleMessageDecoder : Decoder res -> ResponseDecoder res
singleMessageDecoder decoder =
    Array.get 0
        >> Maybe.andThen (Protobuf.Decode.decode decoder)


streamToListDecoder : Decoder res -> ResponseDecoder (List res)
streamToListDecoder decoder =
    Array.toList
        >> List.map (Protobuf.Decode.decode decoder)
        >> combineMaybes


combineMaybes : List (Maybe a) -> Maybe (List a)
combineMaybes =
    let
        helper : List a -> List (Maybe a) -> Maybe (List a)
        helper acc maybes =
            case maybes of
                [] ->
                    Just <| List.reverse acc

                Nothing :: _ ->
                    Nothing

                (Just x) :: xs ->
                    helper (x :: acc) xs
    in
    helper []
