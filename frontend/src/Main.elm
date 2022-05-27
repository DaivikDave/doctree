module Main exposing (Model, Msg(..), init, main, subscriptions, update, view)

import API
import APISchema
import Browser
import Browser.Navigation as Nav
import Flags exposing (Flags)
import Home
import Html exposing (..)
import Html.Attributes exposing (..)
import Http
import Project
import Route exposing (Route(..), toRoute)
import Search
import Task
import Url
import Util


main : Program Flags Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }


type alias Model =
    { flags : Flags.Decoded
    , key : Nav.Key
    , url : Url.Url
    , route : Route
    , projectList : Maybe (Result Http.Error (List String))
    , search : Search.Model
    , currentProjectName : Maybe String
    , projectIndexes : Maybe (Result Http.Error APISchema.ProjectIndexes)
    , projectPage : Maybe Project.Model
    }


init : Flags -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    let
        ( searchModel, searchCmd ) =
            Search.init Nothing

        route =
            toRoute (Url.toString url)

        projectPage =
            Maybe.map (\v -> Project.init v) (Project.fromRoute route)
    in
    ( { flags = Flags.decode flags
      , key = key
      , url = url
      , route = route
      , projectList = Nothing
      , search = searchModel
      , currentProjectName = Nothing
      , projectIndexes = Nothing
      , projectPage = Maybe.map (\( subModel, _ ) -> subModel) projectPage
      }
    , Cmd.batch
        [ case route of
            Route.Home _ ->
                API.fetchProjectList GotProjectList

            _ ->
                Cmd.none
        , Cmd.map (\v -> SearchMsg v) searchCmd
        , case projectPage of
            Just ( _, subCmds ) ->
                Cmd.map (\msg -> ProjectPage msg) subCmds

            Nothing ->
                Cmd.none
        ]
    )


type Msg
    = NoOp
    | LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | GotProjectList (Result Http.Error (List String))
    | SearchMsg Search.Msg
    | GetProject String
    | GotProject (Result Http.Error APISchema.ProjectIndexes)
    | ProjectPage Project.Msg
    | ProjectPageUpdate Project.UpdateMsg


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model, Nav.pushUrl model.key (Url.toString url) )

                Browser.External href ->
                    ( model, Nav.load href )

        UrlChanged url ->
            ( { model | url = url }
            , Cmd.none
            )

        GotProjectList projectList ->
            ( { model | projectList = Just projectList }, Cmd.none )

        SearchMsg searchMsg ->
            let
                ( searchModel, searchCmd ) =
                    Search.update searchMsg model.search
            in
            ( { model | search = searchModel }
            , Cmd.map (\v -> SearchMsg v) searchCmd
            )

        GetProject projectName ->
            Maybe.withDefault
                -- No project loaded yet, request it.
                ( { model | currentProjectName = Just projectName }
                , API.fetchProject GotProject projectName
                )
                -- Loaded already
                (model.currentProjectName
                    |> Maybe.andThen (Util.maybeEquals projectName)
                    |> Maybe.andThen (\_ -> model.projectIndexes)
                    |> Maybe.map (\_ -> ( model, Cmd.none ))
                )

        GotProject result ->
            ( { model | projectIndexes = Just result }, Cmd.none )

        ProjectPage m ->
            ( model, Task.succeed () |> Task.perform (\_ -> mapProjectMsg m) )

        ProjectPageUpdate subMsg ->
            case model.projectPage of
                Just oldSubModel ->
                    let
                        ( subModel, subCmds ) =
                            Project.update model.key subMsg oldSubModel
                    in
                    ( { model | projectPage = Just subModel }, Cmd.map (\m -> ProjectPage m) subCmds )

                Nothing ->
                    ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


view : Model -> Browser.Document Msg
view model =
    case model.route of
        -- TODO: use search query param
        Route.Home _ ->
            let
                page =
                    Home.view model.flags.cloudMode
                        { projectList = model.projectList
                        , search = model.search
                        }
            in
            { title = page.title
            , body =
                List.map
                    (\v ->
                        Html.map
                            (\msg ->
                                case msg of
                                    Home.SearchMsg m ->
                                        SearchMsg m
                            )
                            v
                    )
                    page.body
            }

        Route.Project projectName searchQuery ->
            case model.projectPage of
                Just subModel ->
                    let
                        page =
                            Project.viewProject model.search
                                model.projectIndexes
                                projectName
                                searchQuery
                                model.flags.cloudMode
                                subModel
                    in
                    { title = page.title
                    , body = List.map (\v -> Html.map mapProjectMsg v) page.body
                    }

                Nothing ->
                    { title = "doctree"
                    , body =
                        [ text "error: view Route.Project when model empty!" ]
                    }

        _ ->
            { title = "doctree"
            , body =
                [ text "TODO: "
                , b [] [ text (Route.toString model.route) ]
                ]
            }


mapProjectMsg : Project.Msg -> Msg
mapProjectMsg msg =
    case msg of
        Project.NoOp ->
            NoOp

        Project.SearchMsg m ->
            SearchMsg m

        Project.GetProject projectName ->
            GetProject projectName

        Project.GotPage page ->
            ProjectPageUpdate (Project.UpdateGotPage page)

        Project.ObservePage ->
            ProjectPageUpdate Project.UpdateObservePage

        Project.OnObserved result ->
            ProjectPageUpdate (Project.UpdateOnObserved result)
