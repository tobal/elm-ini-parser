module ElmIniParser exposing (KeyAndValue(..), Ini(..), Section(..), ConfigValues, configValues, ini, kv, prepareForIniParsing, section, sectionTitle, sections)

import Dict exposing (Dict)
import Parser exposing (..)
import Set
import String as S


type Ini
    = WithGlobals ConfigValues (List Section)
    | WithoutGlobals (List Section)


type Section
    = Section String ConfigValues


type alias ConfigValues =
    Dict String (Maybe String)


joinIniLineBreaks : String -> String
joinIniLineBreaks =
    S.replace "\\\n" ""


removeLineEndingComments : String -> String
removeLineEndingComments =
    S.lines
        >> List.map
            (S.split ";"
                >> (\splitstr ->
                        case splitstr of
                            [] ->
                                ""

                            h :: tail ->
                                h
                   )
            )
        >> S.join "\n"


removeFullLineComments : String -> String
removeFullLineComments =
    S.lines
        >> List.filter (S.startsWith ";" >> not)
        >> S.join "\n"


removeEmptyLines : String -> String
removeEmptyLines =
    S.lines
        >> List.filter (S.isEmpty >> not)
        >> S.join "\n"


trimWhitespace : String -> String
trimWhitespace =
    S.lines
        >> List.map S.trim
        >> S.join "\n"


prepareForIniParsing : String -> String
prepareForIniParsing =
    removeLineEndingComments
        >> trimWhitespace
        >> joinIniLineBreaks
        >> removeEmptyLines
        >> removeFullLineComments


type KeyAndValue
    = KV String (Maybe String)


kv : Parser KeyAndValue
kv =
    let
        valueStringParser : Parser String
        valueStringParser =
            getChompedString <|
                succeed ()
                    |. chompUntilEndOr "\n"

        valParser : Parser (Maybe String)
        valParser =
            map
                (\chomped ->
                    if S.isEmpty chomped then
                        Nothing

                    else
                        Just <| String.trimLeft chomped
                )
                valueStringParser
    in
    succeed KV
        |= variable
            { start = Char.isAlphaNum
            , inner = Char.isAlphaNum
            , reserved = Set.empty
            }
        |. spaces
        |. symbol "="
        |= valParser
        |. lineComment ""
        |. oneOf [ symbol "\n", succeed () ]


sectionTitle : Parser String
sectionTitle =
    let
        myChomper =
            getChompedString <|
                succeed ()
                    |. chompUntil "]"

        titleChomper : Parser String
        titleChomper =
            map
                (\titleWithWhitespace -> String.trimRight titleWithWhitespace)
                myChomper
    in
    succeed identity
        |. spaces
        |. symbol "["
        |. spaces
        |= titleChomper
        |. lineComment "]"
        |. oneOf [ symbol "\n", succeed () ]


configValues : Parser ConfigValues
configValues =
    let
        listParser : Parser (List KeyAndValue)
        listParser =
            loop [] pairsHelp

        pairsHelp : List KeyAndValue -> Parser (Step (List KeyAndValue) (List KeyAndValue))
        pairsHelp pairs =
            oneOf
                [ map
                    (\pair -> Loop (pair :: pairs))
                    kv
                , succeed () |> map (\_ -> Done <| List.reverse pairs)
                ]
    in
    map
        (\kvlist ->
            List.map (\(KV key value) -> ( key, value )) kvlist
                |> Dict.fromList
        )
        listParser


section : Parser Section
section =
    succeed Section
        |= sectionTitle
        |= configValues


sections : Parser (List Section)
sections =
    let
        sectionsHelper : List Section -> Parser (Step (List Section) (List Section))
        sectionsHelper parsedSections =
            oneOf
                [ map
                    (\s -> Loop (s :: parsedSections))
                    section
                , succeed () |> map (\_ -> Done <| List.reverse parsedSections)
                ]
    in
    loop [] sectionsHelper


ini : Parser Ini
ini =
    oneOf
        [ succeed WithGlobals
            |= configValues
            |= sections
        , succeed WithoutGlobals
            |= sections
        ]
