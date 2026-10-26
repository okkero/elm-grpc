module Grpc.Streaming exposing
    ( Streaming, ServerStream, fromRequest
    , map, filter, take
    , foldl, toList
    )

{-| Read the response of a server-streaming rpc.

A `Streaming` describes a request and what to do with the messages it responds with. A terminal operation, such as
`foldl` or `toList`, turns it into a `Task`, and nothing is sent until that task is performed. The response is
received in full before any message is read, since Elm hands over a response body only once it is complete. Its
messages are then decoded one at a time, as the operations ask for them, so `take` stops decoding once it has enough.
This suits finite streams, not ones that stay open, since the task completes only when the response does.

    Grpc.new Proto.Orders.streamOrders request
        |> Grpc.Streaming.fromRequest
        |> Grpc.Streaming.filter .open
        |> Grpc.Streaming.take 10
        |> Grpc.Streaming.toList


# Building

@docs Streaming, ServerStream, fromRequest


# Transforming

@docs map, filter, take


# Reading

@docs foldl, toList

-}

import Array exposing (Array)
import Bytes exposing (Bytes)
import Grpc
import Grpc.Internal
import Protobuf.Decode exposing (Decoder)
import Task exposing (Task)


{-| A server-streaming request that has not been sent, and the operations to apply to the messages it responds with.
-}
type Streaming a
    = Streaming (Task Grpc.Error (Source a))


{-| The messages of a response that have not been read yet, each produced only when it is asked for.
-}
type Source a
    = Source (() -> Step a)


type Step a
    = Done
    | Yield a (Source a)
    | Fail Grpc.Error


{-| The response of a server-streaming rpc, as generated code types it.
-}
type alias ServerStream res =
    Grpc.Internal.ServerStream res


{-| Describe a request to a server-streaming rpc, without sending it.
-}
fromRequest : Grpc.RpcRequest req (ServerStream res) -> Streaming res
fromRequest request =
    Streaming
        (Grpc.toTask request
            |> Task.map
                (\(Grpc.Internal.ServerStream encodedMessages decoder) ->
                    decodedMessagesFrom 0 encodedMessages decoder
                )
        )


decodedMessagesFrom : Int -> Array Bytes -> Decoder res -> Source res
decodedMessagesFrom index encodedMessages decoder =
    Source
        (\() ->
            case Array.get index encodedMessages of
                Nothing ->
                    Done

                Just encodedMessage ->
                    case Protobuf.Decode.decode decoder encodedMessage of
                        Just message ->
                            Yield message (decodedMessagesFrom (index + 1) encodedMessages decoder)

                        Nothing ->
                            Fail (Grpc.BadBody encodedMessage)
        )


{-| Transform each message.
-}
map : (a -> b) -> Streaming a -> Streaming b
map transform (Streaming request) =
    Streaming (Task.map (mapSource transform) request)


mapSource : (a -> b) -> Source a -> Source b
mapSource transform (Source next) =
    Source
        (\() ->
            case next () of
                Done ->
                    Done

                Yield message rest ->
                    Yield (transform message) (mapSource transform rest)

                Fail error ->
                    Fail error
        )


{-| Keep only the messages that satisfy the predicate.
-}
filter : (a -> Bool) -> Streaming a -> Streaming a
filter isKept (Streaming request) =
    Streaming (Task.map (filterSource isKept) request)


filterSource : (a -> Bool) -> Source a -> Source a
filterSource isKept source =
    let
        nextKept (Source next) =
            case next () of
                Done ->
                    Done

                Yield message rest ->
                    if isKept message then
                        Yield message (filterSource isKept rest)

                    else
                        -- Skipping a filtered-out message must stay a self call in tail position,
                        -- which Elm compiles to a loop. Otherwise each skipped message adds a
                        -- stack frame, and a long run of them overflows the stack.
                        nextKept rest

                Fail error ->
                    Fail error
    in
    Source (\() -> nextKept source)


{-| Keep at most the given number of messages. The messages after them are never decoded.
-}
take : Int -> Streaming a -> Streaming a
take count (Streaming request) =
    Streaming (Task.map (takeSource count) request)


takeSource : Int -> Source a -> Source a
takeSource count (Source next) =
    Source
        (\() ->
            if count <= 0 then
                Done

            else
                case next () of
                    Done ->
                        Done

                    Yield message rest ->
                        Yield message (takeSource (count - 1) rest)

                    Fail error ->
                        Fail error
        )


{-| A task that sends the request and folds its messages from the first to the last. It fails if the request fails,
or with `BadBody` carrying the message if a message it reads does not decode.
-}
foldl : (a -> acc -> acc) -> acc -> Streaming a -> Task Grpc.Error acc
foldl accumulate initial (Streaming request) =
    request
        |> Task.andThen
            (\source ->
                case foldlSource accumulate initial source of
                    Ok result ->
                        Task.succeed result

                    Err error ->
                        Task.fail error
            )


foldlSource : (a -> acc -> acc) -> acc -> Source a -> Result Grpc.Error acc
foldlSource accumulate acc (Source next) =
    case next () of
        Done ->
            Ok acc

        Yield message rest ->
            -- This self call must stay in tail position, which Elm compiles to a loop. Otherwise
            -- each message adds a stack frame, and a long stream overflows the stack.
            foldlSource accumulate (accumulate message acc) rest

        Fail error ->
            Err error


{-| A task that sends the request and collects its messages in order.
-}
toList : Streaming a -> Task Grpc.Error (List a)
toList =
    foldl (::) [] >> Task.map List.reverse
