port module Main exposing (main)

import Browser
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Decode as Decode exposing (Decoder)


-- PORTS


port sendMessage : String -> Cmd msg


port messageReceiver : (String -> msg) -> Sub msg


port connectionStatus : (Bool -> msg) -> Sub msg



-- MAIN


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }



-- MODEL


type alias Message =
    { messageType : MessageType
    , text : String
    , clientId : Maybe Int
    }


type MessageType
    = SystemMessage
    | ChatMessage


type alias Model =
    { messages : List Message
    , input : String
    , connected : Bool
    , myClientId : Maybe Int
    }


init : () -> ( Model, Cmd Msg )
init _ =
    ( { messages = []
      , input = ""
      , connected = False
      , myClientId = Nothing
      }
    , Cmd.none
    )



-- UPDATE


type Msg
    = InputChanged String
    | SendClicked
    | MessageReceived String
    | ConnectionChanged Bool


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        InputChanged newInput ->
            ( { model | input = newInput }, Cmd.none )

        SendClicked ->
            if String.isEmpty (String.trim model.input) then
                ( model, Cmd.none )

            else
                ( { model | input = "" }
                , sendMessage model.input
                )

        MessageReceived jsonString ->
            case Decode.decodeString messageDecoder jsonString of
                Ok message ->
                    let
                        -- Try to extract our client ID from welcome messages
                        newClientId =
                            case ( message.messageType, model.myClientId ) of
                                ( SystemMessage, Nothing ) ->
                                    extractClientId message.text

                                _ ->
                                    model.myClientId
                    in
                    ( { model
                        | messages = model.messages ++ [ message ]
                        , myClientId = newClientId
                      }
                    , Cmd.none
                    )

                Err _ ->
                    ( model, Cmd.none )

        ConnectionChanged isConnected ->
            let
                statusMessage =
                    if isConnected then
                        { messageType = SystemMessage
                        , text = "Connected to server"
                        , clientId = Nothing
                        }

                    else
                        { messageType = SystemMessage
                        , text = "Disconnected from server"
                        , clientId = Nothing
                        }
            in
            ( { model
                | connected = isConnected
                , messages = model.messages ++ [ statusMessage ]
              }
            , Cmd.none
            )


extractClientId : String -> Maybe Int
extractClientId text =
    -- Try to extract client ID from "You are client #X" message
    if String.contains "You are client #" text then
        text
            |> String.split "#"
            |> List.drop 1
            |> List.head
            |> Maybe.andThen
                (\s ->
                    s
                        |> String.filter Char.isDigit
                        |> String.toInt
                )

    else
        Nothing


messageDecoder : Decoder Message
messageDecoder =
    Decode.map3 Message
        (Decode.field "type" messageTypeDecoder)
        (Decode.field "text" Decode.string)
        (Decode.maybe (Decode.field "clientId" Decode.int))


messageTypeDecoder : Decoder MessageType
messageTypeDecoder =
    Decode.string
        |> Decode.andThen
            (\typeStr ->
                case typeStr of
                    "system" ->
                        Decode.succeed SystemMessage

                    "message" ->
                        Decode.succeed ChatMessage

                    _ ->
                        Decode.succeed ChatMessage
            )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ messageReceiver MessageReceived
        , connectionStatus ConnectionChanged
        ]



-- VIEW


view : Model -> Html Msg
view model =
    div [ class "chat-container" ]
        [ viewHeader model
        , viewMessages model
        , viewInputArea model
        ]


viewHeader : Model -> Html Msg
viewHeader model =
    div [ class "chat-header" ]
        [ h1 [] [ text "Roc Chat" ]
        , div
            [ class "status"
            , classList
                [ ( "connected", model.connected )
                , ( "disconnected", not model.connected )
                ]
            ]
            [ text
                (if model.connected then
                    case model.myClientId of
                        Just clientId ->
                            "● Connected as Client #" ++ String.fromInt clientId

                        Nothing ->
                            "● Connected"

                 else
                    "○ Disconnected"
                )
            ]
        ]


viewMessages : Model -> Html Msg
viewMessages model =
    div [ class "messages", id "messages" ]
        (List.map (viewMessage model.myClientId) model.messages)


viewMessage : Maybe Int -> Message -> Html Msg
viewMessage myClientId message =
    case message.messageType of
        SystemMessage ->
            div [ class "message system" ]
                [ text message.text ]

        ChatMessage ->
            let
                isOwn =
                    case ( myClientId, message.clientId ) of
                        ( Just myId, Just msgId ) ->
                            myId == msgId

                        _ ->
                            False

                messageClass =
                    if isOwn then
                        "message own"

                    else
                        "message other"
            in
            div [ class messageClass ]
                [ case message.clientId of
                    Just clientId ->
                        div [ class "sender" ]
                            [ text
                                (if isOwn then
                                    "You"

                                 else
                                    "Client #" ++ String.fromInt clientId
                                )
                            ]

                    Nothing ->
                        text ""
                , text message.text
                ]


viewInputArea : Model -> Html Msg
viewInputArea model =
    div [ class "input-area" ]
        [ input
            [ type_ "text"
            , placeholder "Type a message..."
            , value model.input
            , onInput InputChanged
            , onEnter SendClicked
            , disabled (not model.connected)
            ]
            []
        , button
            [ onClick SendClicked
            , disabled (not model.connected || String.isEmpty (String.trim model.input))
            ]
            [ text "Send" ]
        ]


onEnter : Msg -> Attribute Msg
onEnter msg =
    on "keydown"
        (Decode.field "key" Decode.string
            |> Decode.andThen
                (\key ->
                    if key == "Enter" then
                        Decode.succeed msg

                    else
                        Decode.fail "Not Enter"
                )
        )
