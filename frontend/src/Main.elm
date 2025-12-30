port module Main exposing (main)

import Browser
import Element exposing (..)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Html
import Html.Attributes
import Html.Events
import Json.Decode as Decode exposing (Decoder)


-- PORTS


port sendMessage : String -> Cmd msg


port messageReceiver : (String -> msg) -> Sub msg


port connectionStatus : (Bool -> msg) -> Sub msg


port scrollToBottom : () -> Cmd msg



-- MAIN


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view >> layout []
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
    | NoOp


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
                    , scrollToBottom ()
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
            , scrollToBottom ()
            )

        NoOp ->
            ( model, Cmd.none )


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


view : Model -> Element Msg
view model =
    el
        [ width fill
        , height fill
        , Background.gradient
            { angle = 2.36
            , steps = [ rgb255 102 126 234, rgb255 118 75 162 ]
            }
        , padding 20
        , clip
        ]
        (el [ centerX, centerY, width (fill |> maximum 600) ]
            (column
                [ width fill
                , height (px 500)
                , Background.color (rgb255 255 255 255)
                , Border.rounded 16
                , Border.shadow
                    { offset = ( 0, 10 )
                    , size = 0
                    , blur = 30
                    , color = rgba 0 0 0 0.2
                    }
                , clip
                ]
                [ viewHeader model
                , viewMessages model
                , viewInputArea model
                ]
            )
        )


viewHeader : Model -> Element Msg
viewHeader model =
    row
        [ width fill
        , height (px 64)
        , paddingXY 20 0
        , Background.color (rgb255 102 126 234)
        , spacing 10
        ]
        [ el
            [ Font.size 24
            , Font.bold
            , Font.color (rgb255 255 255 255)
            ]
            (text "Roc Chat")
        , el [ alignRight ]
            (row
                [ spacing 8
                , Font.size 14
                , Font.color (rgb255 255 255 255)
                ]
                [ el
                    [ Font.color
                        (if model.connected then
                            rgb255 144 238 144

                         else
                            rgb255 255 99 71
                        )
                    ]
                    (text
                        (if model.connected then
                            "●"

                         else
                            "○"
                        )
                    )
                , text
                    (if model.connected then
                        case model.myClientId of
                            Just clientId ->
                                "Connected as Client #" ++ String.fromInt clientId

                            Nothing ->
                                "Connected"

                     else
                        "Disconnected"
                    )
                ]
            )
        ]


viewMessages : Model -> Element Msg
viewMessages model =
    Element.html
        (Html.div
            [ Html.Attributes.id "messages"
            , Html.Attributes.style "width" "100%"
            , Html.Attributes.style "height" "356px"
            , Html.Attributes.style "overflow-y" "auto"
            , Html.Attributes.style "background-color" "#f8f9fa"
            , Html.Attributes.style "padding" "16px"
            , Html.Attributes.style "box-sizing" "border-box"
            ]
            (if List.isEmpty model.messages then
                [ Html.div
                    [ Html.Attributes.style "text-align" "center"
                    , Html.Attributes.style "color" "#aaa"
                    , Html.Attributes.style "font-style" "italic"
                    ]
                    [ Html.text "No messages yet..." ]
                ]

             else
                List.map (viewMessageHtml model.myClientId) model.messages
            )
        )


viewMessageHtml : Maybe Int -> Message -> Html.Html Msg
viewMessageHtml myClientId message =
    case message.messageType of
        SystemMessage ->
            Html.div
                [ Html.Attributes.style "text-align" "center"
                , Html.Attributes.style "font-size" "13px"
                , Html.Attributes.style "color" "#888"
                , Html.Attributes.style "font-style" "italic"
                , Html.Attributes.style "padding" "6px 12px"
                , Html.Attributes.style "background-color" "#f5f5f5"
                , Html.Attributes.style "border-radius" "12px"
                , Html.Attributes.style "margin-bottom" "12px"
                ]
                [ Html.text message.text ]

        ChatMessage ->
            let
                isOwn =
                    case ( myClientId, message.clientId ) of
                        ( Just myId, Just msgId ) ->
                            myId == msgId

                        _ ->
                            False
            in
            Html.div
                [ Html.Attributes.style "display" "flex"
                , Html.Attributes.style "flex-direction" "column"
                , Html.Attributes.style "align-items"
                    (if isOwn then
                        "flex-end"

                     else
                        "flex-start"
                    )
                , Html.Attributes.style "margin-bottom" "12px"
                ]
                [ case message.clientId of
                    Just clientId ->
                        Html.div
                            [ Html.Attributes.style "font-size" "11px"
                            , Html.Attributes.style "color" "#888"
                            , Html.Attributes.style "margin-bottom" "4px"
                            ]
                            [ Html.text
                                (if isOwn then
                                    "You"

                                 else
                                    "Client #" ++ String.fromInt clientId
                                )
                            ]

                    Nothing ->
                        Html.text ""
                , Html.div
                    [ Html.Attributes.style "padding" "10px 14px"
                    , Html.Attributes.style "border-radius" "16px"
                    , Html.Attributes.style "background-color"
                        (if isOwn then
                            "#667eea"

                         else
                            "#f0f0f0"
                        )
                    , Html.Attributes.style "color"
                        (if isOwn then
                            "#fff"

                         else
                            "#333"
                        )
                    ]
                    [ Html.text message.text ]
                ]


viewMessage : Maybe Int -> Message -> Element Msg
viewMessage myClientId message =
    case message.messageType of
        SystemMessage ->
            el
                [ centerX
                , Font.size 13
                , Font.color (rgb255 136 136 136)
                , Font.italic
                , paddingXY 12 6
                , Background.color (rgb255 245 245 245)
                , Border.rounded 12
                ]
                (text message.text)

        ChatMessage ->
            let
                isOwn =
                    case ( myClientId, message.clientId ) of
                        ( Just myId, Just msgId ) ->
                            myId == msgId

                        _ ->
                            False
            in
            column
                [ if isOwn then
                    alignRight

                  else
                    alignLeft
                , spacing 4
                ]
                [ case message.clientId of
                    Just clientId ->
                        el
                            [ Font.size 11
                            , Font.color (rgb255 136 136 136)
                            , if isOwn then
                                alignRight

                              else
                                alignLeft
                            ]
                            (text
                                (if isOwn then
                                    "You"

                                 else
                                    "Client #" ++ String.fromInt clientId
                                )
                            )

                    Nothing ->
                        none
                , el
                    [ paddingXY 14 10
                    , Border.rounded 16
                    , if isOwn then
                        Background.color (rgb255 102 126 234)

                      else
                        Background.color (rgb255 240 240 240)
                    , if isOwn then
                        Font.color (rgb255 255 255 255)

                      else
                        Font.color (rgb255 51 51 51)
                    ]
                    (text message.text)
                ]


viewInputArea : Model -> Element Msg
viewInputArea model =
    row
        [ width fill
        , height (px 80)
        , paddingXY 16 16
        , spacing 12
        , Border.widthEach { top = 1, bottom = 0, left = 0, right = 0 }
        , Border.color (rgb255 238 238 238)
        , Background.color (rgb255 250 250 250)
        ]
        [ Input.text
            [ width fill
            , height (px 48)
            , paddingXY 16 12
            , Border.rounded 24
            , Border.width 1
            , Border.color (rgb255 221 221 221)
            , Background.color (rgb255 255 255 255)
            , htmlAttribute (onEnterAttr SendClicked)
            ]
            { onChange = InputChanged
            , text = model.input
            , placeholder = Just (Input.placeholder [] (text "Type a message..."))
            , label = Input.labelHidden "Message input"
            }
        , Input.button
            [ paddingXY 24 12
            , height (px 48)
            , Border.rounded 24
            , Background.color
                (if model.connected && not (String.isEmpty (String.trim model.input)) then
                    rgb255 102 126 234

                 else
                    rgb255 204 204 204
                )
            , Font.color (rgb255 255 255 255)
            , Font.bold
            , mouseOver
                [ Background.color
                    (if model.connected && not (String.isEmpty (String.trim model.input)) then
                        rgb255 85 105 200

                     else
                        rgb255 204 204 204
                    )
                ]
            ]
            { onPress =
                if model.connected && not (String.isEmpty (String.trim model.input)) then
                    Just SendClicked

                else
                    Nothing
            , label = text "Send"
            }
        ]


onEnterAttr : Msg -> Html.Attribute Msg
onEnterAttr msg =
    Html.Events.on "keydown"
        (Decode.field "key" Decode.string
            |> Decode.andThen
                (\key ->
                    if key == "Enter" then
                        Decode.succeed msg

                    else
                        Decode.fail "Not Enter"
                )
        )
