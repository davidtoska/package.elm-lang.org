module Component.Documentation where

import Char
import Color
import Dict
import Graphics.Element exposing (..)
import Json.Decode exposing (..)
import Markdown
import String
import Text

import ColorScheme as C


type alias DocDict =
    Dict.Dict String (Text.Text, Maybe (String, Int), String)


toDocDict : Documentation -> DocDict
toDocDict docs =
  let toPairs view getAssocPrec entries =
          List.map (\entry -> (entry.name, (view entry, getAssocPrec entry, entry.comment))) entries
  in
      Dict.fromList <|
        toPairs viewAlias (always Nothing) docs.aliases
        ++ toPairs viewUnion (always Nothing) docs.unions
        ++ toPairs viewValue .assocPrec docs.values


-- MODEL

type alias Documentation =
    { name : String
    , comment : String
    , aliases : List Alias
    , unions : List Union
    , values : List Value
    }


documentation : Decoder Documentation
documentation =
  object5 Documentation
    ("name" := string)
    ("comment" := string)
    ("aliases" := list alias)
    ("types" := list union)
    ("values" := list value)


valueList : Decoder (String, List String)
valueList =
  let
    nameList =
      list ("name" := string)

    allNames =
      object3 (\x y z -> x ++ y ++ z)
        ("aliases" := nameList)
        ("types" := nameList)
        ("values" := nameList)
  in
    object2 (,) ("name" := string) allNames


type alias Alias =
    { name : String
    , comment : String
    , args : List String
    , tipe : Type
    }


alias : Decoder Alias
alias =
  object4 Alias
    ("name" := string)
    ("comment" := string)
    ("args" := list string)
    ("type" := string)


type alias Union =
    { name : String
    , comment : String
    , args : List String
    , cases : List (String, List Type)
    }


union : Decoder Union
union =
  object4 Union
    ("name" := string)
    ("comment" := string)
    ("args" := list string)
    ("cases" := list (tuple2 (,) string (list string)))


type alias Value =
    { name : String
    , comment : String
    , tipe : Type
    , assocPrec : Maybe (String,Int)
    }


value : Decoder Value
value =
  object4 Value
    ("name" := string)
    ("comment" := string)
    ("type" := string)
    assocPrec


assocPrec : Decoder (Maybe (String, Int))
assocPrec =
  maybe <|
    object2 (,)
      ("associativity" := string)
      ("precedence" := int)


type alias Type = String


-- VIEW

options : Markdown.Options
options =
  let
    defaults = Markdown.defaultOptions
  in
    { defaults | sanitize <- True }


viewEntry : Int -> String -> (Text.Text, Maybe (String, Int), String) -> Element
viewEntry innerWidth name (annotation, maybeAssocPrec, comment) =
  let
    rawAssocPrec =
      case maybeAssocPrec of
        Nothing -> empty
        Just (assoc, prec) ->
          assoc ++ "-associative / precedence " ++ toString prec
            |> Text.fromString
            |> Text.height 12
            |> rightAligned

    assocPrecWidth =
      widthOf rawAssocPrec + 20

    assocPrec =
      container assocPrecWidth (min annotationHeight 24) middle rawAssocPrec

    annotationText =
      leftAligned (Text.monospace annotation)
        |> width annotationWidth

    annotationPadding = 10

    annotationWidth =
      innerWidth - annotationPadding - assocPrecWidth

    annotationHeight =
      heightOf annotationText + 8

    commentElement =
      if String.isEmpty comment
          then empty
          else
              flow right
              [ spacer 40 1
              , width (innerWidth - 40) (Markdown.toElementWith options comment)
              ]

    annotationBar =
      flow right
      [ spacer annotationPadding annotationHeight
      , container annotationWidth annotationHeight midLeft annotationText
      , assocPrec
      ]
  in
    flow down
      [ tag name (color C.mediumGrey (spacer innerWidth 1))
      , annotationBar
      , commentElement
      , spacer innerWidth 50
      ]


-- VIEW ALIASES

viewAlias : Alias -> Text.Text
viewAlias alias =
  Text.concat
    [ green "type alias "
    , Text.link ("#" ++ alias.name) (Text.bold (Text.fromString alias.name))
    , Text.fromString (String.concat (List.map ((++) " ") alias.args))
    , green " = "
    , case String.uncons alias.tipe of
        Just ('{', _) ->
          viewRecordType alias.tipe

        _ ->
          typeToText alias.tipe
    ]


-- VIEW UNIONS

viewUnion : Union -> Text.Text
viewUnion union =
  let
    seperators =
      green "\n    = "
      :: List.repeat (List.length union.cases - 1) (green "\n    | ")
  in
    Text.concat
      [ green "type "
      , Text.link ("#" ++ union.name) (Text.bold (Text.fromString union.name))
      , Text.fromString (String.concat (List.map ((++) " ") union.args))
      , Text.concat (List.map2 (++) seperators (List.map viewCase union.cases))
      ]


viewCase : (String, List Type) -> Text.Text
viewCase (tag, args) =
  List.map viewArg args
    |> (::) (Text.fromString tag)
    |> List.intersperse (Text.fromString " ")
    |> Text.concat


viewArg : String -> Text.Text
viewArg tipe =
  let
    (Just (c,_)) =
      String.uncons tipe
  in
    if c == '(' || c == '{' || not (String.contains " " tipe) then
      typeToText tipe
    else
      typeToText ("(" ++ tipe ++ ")")


-- VIEW VALUES

viewValue : Value -> Text.Text
viewValue value =
  Text.concat
    [ Text.link ("#" ++ value.name) (Text.bold (viewVar value.name))
    , viewFunctionType value.tipe
    ]


viewVar : String -> Text.Text
viewVar str =
  Text.fromString <|
    case String.uncons str of
      Nothing ->
        str

      Just (c, _) ->
        if isVarChar c then str else "(" ++ str ++ ")"


isVarChar : Char -> Bool
isVarChar c =
  Char.isLower c || Char.isUpper c || Char.isDigit c || c == '_' || c == '\''


-- VIEW TYPES

viewRecordType : String -> Text.Text
viewRecordType tipe =
  splitRecord tipe
    |> List.map (typeToText << (++) "\n    ")
    |> Text.concat


viewFunctionType : Type -> Text.Text
viewFunctionType tipe =
  if String.length tipe < 80 then
    green " : " ++ typeToText tipe
  else
    let
      parts =
        splitArgs tipe

      seperators =
        "\n    :  "
        :: List.repeat (List.length parts - 1) "\n    ->"
    in
      Text.concat (List.map2 (\sep part -> typeToText (sep ++ part)) seperators parts)


-- TYPE TO TEXT

typeToText : String -> Text.Text
typeToText tipe =
  String.words tipe
    |> List.map dropQualifier
    |> String.join " "
    |> String.split "->"
    |> List.map prettyColons
    |> List.intersperse (green "->")
    |> Text.concat


prettyColons : String -> Text.Text
prettyColons tipe =
  String.split ":" tipe
    |> List.map Text.fromString
    |> List.intersperse (green ":")
    |> Text.concat


dropQualifier : String -> String
dropQualifier token =
  Maybe.withDefault token (last (String.split "." token))


last : List a -> Maybe a
last list =
  case list of
    [] ->
      Nothing

    [x] ->
      Just x

    _ :: xs ->
      last xs


-- VIEW HELPERS

green : String -> Text.Text
green str =
  Text.color (C.green) (Text.fromString str)


-- SPLITTING TYPES

type alias SplitState =
  { parenDepth : Int
  , bracketDepth : Int
  , currentChunk : String
  , chunks : List String
  }


updateDepths : Char -> SplitState -> SplitState
updateDepths char state =
  case char of
    '(' ->
        { state | parenDepth <- state.parenDepth + 1 }

    ')' ->
        { state | parenDepth <- state.parenDepth - 1 }

    '{' ->
        { state | bracketDepth <- state.bracketDepth + 1 }

    '}' ->
        { state | bracketDepth <- state.bracketDepth - 1 }

    _ ->
        state


-- SPLIT FUNCTION TYPES

splitArgs : String -> List String
splitArgs tipe =
  let
    formattedType =
      String.join "$" (String.split "->" tipe)

    state =
      String.foldl splitArgsHelp (SplitState 0 0 "" []) formattedType
  in
    List.reverse (String.reverse state.currentChunk :: state.chunks)
      |> List.map (String.split "$" >> String.join "->")


splitArgsHelp : Char -> SplitState -> SplitState
splitArgsHelp char startState =
  let
    state =
      updateDepths char startState
  in
    if char == '$' && state.parenDepth == 0 && state.bracketDepth == 0 then
        { state |
            currentChunk <- "",
            chunks <- String.reverse state.currentChunk :: state.chunks
        }
    else
        { state |
            currentChunk <- String.cons char state.currentChunk
        }


-- SPLIT RECORD TYPES

splitRecord : String -> List String
splitRecord tipe =
  let
    state =
      String.foldl splitRecordHelp (SplitState 0 0 "" []) tipe
  in
    List.reverse (String.reverse state.currentChunk :: state.chunks)


splitRecordHelp : Char -> SplitState -> SplitState
splitRecordHelp char startState =
  let
    state =
      updateDepths char startState
  in
    if state.bracketDepth == 0 then
        { state |
            currentChunk <- "}",
            chunks <- String.reverse state.currentChunk :: state.chunks
        }
    else if char == ',' && state.parenDepth == 0 && state.bracketDepth == 1 then
        { state |
            currentChunk <- ",",
            chunks <- String.reverse state.currentChunk :: state.chunks
        }
    else
        { state |
            currentChunk <- String.cons char state.currentChunk
        }
