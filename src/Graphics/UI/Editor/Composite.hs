{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DataKinds #-}
-----------------------------------------------------------------------------
--
-- Module      :  Graphics.UI.Editor.Composite
-- Copyright   :  (c) Juergen Nicklisch-Franken, Hamish Mackenzie
-- License     :  GNU-GPL
--
-- Maintainer  :  <maintainer at leksah.org>
-- Stability   :  provisional
-- Portability :  portable
--
-- | Module for making composite editors
--
-----------------------------------------------------------------------------------

module Graphics.UI.Editor.Composite (
    maybeEditor
,   disableEditor
,   pairEditor
,   tupel3Editor
,   splitEditor
,   eitherOrEditor
,   multisetEditor
,   ColumnDescr(..)

,   filesEditor
,   textsEditor

,   versionEditor
,   versionRangeEditor
,   dependencyEditor
,   dependenciesEditor
) where

import Control.Monad
import Data.IORef
import Data.Maybe
import Data.Text (Text)
import qualified Data.Text as T (pack, unpack, null)

import Default
import Control.Event
import Graphics.UI.Editor.Parameters
import Graphics.UI.Editor.Basics
import Graphics.UI.Editor.MakeEditor
import Graphics.UI.Editor.Simple
import Data.List (sortBy, nub, sort, elemIndex)
import Distribution.Simple
    (orEarlierVersion,
     orLaterVersion,
     VersionRange(..),
     PackageName(..),
     Dependency(..),
     PackageIdentifier(..))
import Distribution.Text (simpleParse, display)
import Distribution.Package (pkgName)
import Data.Version (Version(..))
import MyMissing (forceJust)
import Unsafe.Coerce (unsafeCoerce)
import Debug.Trace (trace)
import GI.Gtk
       (noTreeViewColumn, noAdjustment,
        FileChooserAction, treeModelGetPath,
        treeSelectionGetSelected, treeViewScrollToCell, treeViewGetColumn,
        treeSelectionSelectPath, onButtonClicked, onTreeSelectionChanged,
        treeViewSetHeadersVisible, cellLayoutPackStart,
        cellRendererTextNew, treeViewAppendColumn,
        treeViewColumnSetResizable, treeViewColumnSetTitle,
        treeViewColumnNew, treeSelectionSetMode, treeViewGetSelection,
        scrolledWindowSetMinContentHeight, scrolledWindowSetPolicy,
        scrolledWindowNew, widgetSetSizeRequest, treeViewNewWithModel,
        afterTreeModelRowDeleted, afterTreeModelRowInserted,
        buttonNewWithLabel, hButtonBoxNew, ButtonBox(..), vButtonBoxNew,
        CellRendererText, containerRemove, widgetSetSensitive,
        containerGetChildren, widgetHide, widgetShowAll, boxPackEnd,
        panedPack2, panedPack1, hPanedNew, Paned(..), vPanedNew,
        containerAdd, boxPackStart, vBoxNew, Box(..), hBoxNew, Widget(..))
import Data.GI.Base.ManagedPtr (unsafeCastTo, castTo)
import Data.GI.Base.Attributes
       (AttrLabelProxy(..), AttrOpTag(..), AttrOp(..), AttrOp)
import GI.Gtk.Enums
       (ShadowType(..), SelectionMode(..), PolicyType(..))
import Data.GI.Gtk.ModelView.CellLayout
       (cellLayoutSetAttributes)
import Data.GI.Gtk.ModelView.SeqStore
       (seqStoreAppend, seqStoreClear, seqStoreNew, seqStoreGetValue,
        seqStoreRemove, seqStoreToList, SeqStore(..))
import Data.GI.Gtk.ModelView.Types
       (treePathNewFromIndices', equalManagedPtr)
import GI.Gtk.Structs.TreePath (treePathGetIndices)

_text = AttrLabelProxy :: AttrLabelProxy "text"

--
-- | An editor which composes two subeditors
--
pairEditor :: (Editor alpha, Parameters) -> (Editor beta, Parameters) -> Editor (alpha,beta)
pairEditor (fstEd,fstPara) (sndEd,sndPara) parameters notifier = do
    coreRef <- newIORef Nothing
    noti1   <- emptyNotifier
    noti2   <- emptyNotifier
    mapM_ (propagateEvent notifier [noti1,noti2]) allGUIEvents
    fst@(fstFrame,inj1,ext1) <- fstEd fstPara noti1
    snd@(sndFrame,inj2,ext2) <- sndEd sndPara noti2
    mkEditor
        (\widget (v1,v2) -> do
            core <- readIORef coreRef
            case core of
                Nothing  -> do
                    box <- case getParameter paraDirection parameters of
                        Horizontal -> hBoxNew False 1 >>= unsafeCastTo Box
                        Vertical   -> vBoxNew False 1 >>= unsafeCastTo Box
                    boxPackStart box fstFrame True True 0
                    boxPackStart box sndFrame True True 0
                    containerAdd widget box
                    inj1 v1
                    inj2 v2
                    writeIORef coreRef (Just (fst,snd))
                Just ((_,inj1,_),(_,inj2,_)) -> do
                    inj1 v1
                    inj2 v2)
        (do core <- readIORef coreRef
            case core of
                Nothing -> return Nothing
                Just ((_,_,ext1),(_,_,ext2)) -> do
                    r1 <- ext1
                    r2 <- ext2
                    if isJust r1 && isJust r2
                        then return (Just (fromJust r1,fromJust r2))
                        else return Nothing)
        parameters
        notifier

tupel3Editor :: (Editor alpha, Parameters)
    -> (Editor beta, Parameters)
    -> (Editor gamma, Parameters)
    -> Editor (alpha,beta,gamma)
tupel3Editor p1 p2 p3 parameters notifier = do
    coreRef <- newIORef Nothing
    noti1   <- emptyNotifier
    noti2   <- emptyNotifier
    noti3   <- emptyNotifier
    mapM_ (propagateEvent notifier [noti1,noti2,noti3]) (Clicked : allGUIEvents)
    r1@(frame1,inj1,ext1) <- fst p1 (snd p1) noti1
    r2@(frame2,inj2,ext2) <- fst p2 (snd p2) noti2
    r3@(frame3,inj3,ext3) <- fst p3 (snd p3) noti3
    mkEditor
        (\widget (v1,v2,v3) -> do
            core <- readIORef coreRef
            case core of
                Nothing  -> do
                    box <- case getParameter paraDirection parameters of
                        Horizontal -> hBoxNew False 1 >>= unsafeCastTo Box
                        Vertical   -> vBoxNew False 1 >>= unsafeCastTo Box
                    boxPackStart box frame1 True True 0
                    boxPackStart box frame2 True True 0
                    boxPackStart box frame3 True True 0
                    containerAdd widget box
                    inj1 v1
                    inj2 v2
                    inj3 v3
                    writeIORef coreRef (Just (r1,r2,r3))
                Just ((_,inj1,_),(_,inj2,_),(_,inj3,_)) -> do
                    inj1 v1
                    inj2 v2
                    inj3 v3)
        (do core <- readIORef coreRef
            case core of
                Nothing -> return Nothing
                Just ((_,_,ext1),(_,_,ext2),(_,_,ext3)) -> do
                    r1 <- ext1
                    r2 <- ext2
                    r3 <- ext3
                    if isJust r1 && isJust r2 && isJust r3
                        then return (Just (fromJust r1,fromJust r2, fromJust r3))
                        else return Nothing)
        parameters
        notifier

--
-- | Like a pair editor, but with a moveable split
--
splitEditor :: (Editor alpha, Parameters) -> (Editor beta, Parameters) -> Editor (alpha,beta)
splitEditor (fstEd,fstPara) (sndEd,sndPara) parameters notifier = do
    coreRef <- newIORef Nothing
    noti1   <- emptyNotifier
    noti2   <- emptyNotifier
    mapM_ (propagateEvent notifier [noti1,noti2]) allGUIEvents
    fst@(fstFrame,inj1,ext1) <- fstEd fstPara noti1
    snd@(sndFrame,inj2,ext2) <- sndEd sndPara noti2
    mkEditor
        (\widget (v1,v2) -> do
            core <- readIORef coreRef
            case core of
                Nothing  -> do
                    paned <- case getParameter paraDirection parameters of
                        Horizontal -> vPanedNew >>= unsafeCastTo Paned
                        Vertical   -> hPanedNew >>= unsafeCastTo Paned
                    panedPack1 paned fstFrame True True
                    panedPack2 paned sndFrame True True
                    containerAdd widget paned
                    inj1 v1
                    inj2 v2
                    writeIORef coreRef (Just (fst,snd))
                Just ((_,inj1,_),(_,inj2,_)) -> do
                    inj1 v1
                    inj2 v2)
        (do core <- readIORef coreRef
            case core of
                Nothing -> return Nothing
                Just ((_,_,ext1),(_,_,ext2)) -> do
                    r1 <- ext1
                    r2 <- ext2
                    if isJust r1 && isJust r2
                        then return (Just (fromJust r1,fromJust r2))
                        else return Nothing)
        parameters
        notifier

--
-- | An editor with a subeditor which gets active, when a checkbox is selected
-- or deselected (if the positive Argument is False)
--
maybeEditor :: Default beta => (Editor beta, Parameters) -> Bool -> Text -> Editor (Maybe beta)
maybeEditor (childEdit, childParams) positive boolLabel parameters notifier = do
    coreRef      <- newIORef Nothing
    childRef     <- newIORef Nothing
    notifierBool <- emptyNotifier
    cNoti        <- emptyNotifier
    mkEditor
        (\widget mbVal -> do
            core <- readIORef coreRef
            case core of
                Nothing  -> do
                    box <- case getParameter paraDirection parameters of
                        Horizontal -> hBoxNew False 1 >>= unsafeCastTo Box
                        Vertical   -> vBoxNew False 1 >>= unsafeCastTo Box
                    be@(boolFrame,inj1,ext1) <- boolEditor
                        (paraName <<<- ParaName boolLabel $ emptyParams)
                        notifierBool
                    boxPackStart box boolFrame False False 0
                    containerAdd widget box
                    registerEvent notifierBool Clicked (onClickedHandler widget coreRef childRef cNoti)
                    propagateEvent notifier [notifierBool] MayHaveChanged
                    case mbVal of
                        Nothing -> inj1 (not positive)
                        Just val -> do
                            (childWidget,inj2,ext2) <- getChildEditor childRef childEdit childParams cNoti
                            boxPackEnd box childWidget True True 0
                            widgetShowAll childWidget
                            inj1 positive
                            inj2 val
                    writeIORef coreRef (Just (be,box))
                Just (be@(boolFrame,inj1,extt),box) -> do
                    hasChild <- hasChildEditor childRef
                    case mbVal of
                        Nothing ->
                            if hasChild
                                then do
                                    (childWidget,_,_) <- getChildEditor childRef childEdit childParams cNoti
                                    inj1 (not positive)
                                    widgetHide childWidget
                                else inj1 (not positive)
                        Just val ->
                            if hasChild
                                then do
                                    inj1 positive
                                    (childWidget,inj2,_) <- getChildEditor childRef childEdit childParams cNoti
                                    widgetShowAll childWidget
                                    inj2 val
                                else do
                                    inj1 positive
                                    (childWidget,inj2,_) <- getChildEditor childRef childEdit childParams cNoti
                                    boxPackEnd box childWidget True True 0
                                    widgetShowAll childWidget
                                    inj2 val)
        (do
            core <- readIORef coreRef
            case core of
                Nothing  -> return Nothing
                Just (be@(boolFrame,inj1,ext1),_) -> do
                    bool <- ext1
                    case bool of
                        Nothing -> return Nothing
                        Just bv | bv == positive -> do
                            (_,_,ext2) <- getChildEditor childRef childEdit childParams cNoti
                            value <- ext2
                            case value of
                                Nothing -> return Nothing
                                Just value -> return (Just (Just value))
                        otherwise -> return (Just Nothing))
        parameters
        notifier
    where
    onClickedHandler widget coreRef childRef cNoti event = do
        core <- readIORef coreRef
        case core of
            Nothing  -> error "Impossible"
            Just (be@(boolFrame,inj1,ext1),vBox) -> do
                mbBool <- ext1
                case mbBool of
                    Just bool ->
                        if bool /= positive
                            then do
                                hasChild <- hasChildEditor childRef
                                when hasChild $ do
                                    (childWidget,_,_) <- getChildEditor childRef childEdit childParams cNoti
                                    widgetHide childWidget
                            else do
                                hasChild <- hasChildEditor childRef
                                (childWidget,inj2,ext2) <- getChildEditor childRef childEdit childParams cNoti
                                children <- containerGetChildren vBox
                                unless (any (equalManagedPtr childWidget) children) $
                                    boxPackEnd vBox childWidget False False 0
                                inj2 getDefault
                                widgetShowAll childWidget
                    Nothing -> return ()
                return (event {gtkReturn=True})
    getChildEditor childRef childEditor childParams cNoti =  do
        mb <- readIORef childRef
        case mb of
            Just editor -> return editor
            Nothing -> do
                let val = childEditor
                editor@(_,_,_) <- childEditor childParams cNoti
                mapM_ (propagateEvent notifier [cNoti]) allGUIEvents
                writeIORef childRef (Just editor)
                return editor
    hasChildEditor childRef =  do
        mb <- readIORef childRef
        return (isJust mb)


--
-- | An editor with a subeditor which gets active, when a checkbox is selected
-- or grayed out (if the positive Argument is False)
--
disableEditor :: Default beta => (Editor beta, Parameters) -> Bool -> Text -> Editor (Bool,beta)
disableEditor (childEdit, childParams) positive boolLabel parameters notifier = do
    coreRef      <- newIORef Nothing
    childRef     <- newIORef Nothing
    notifierBool <- emptyNotifier
    cNoti        <- emptyNotifier
    mkEditor
        (\widget mbVal -> do
            core <- readIORef coreRef
            case core of
                Nothing  -> do
                    box <- case getParameter paraDirection parameters of
                        Horizontal -> hBoxNew False 1 >>= unsafeCastTo Box
                        Vertical   -> vBoxNew False 1 >>= unsafeCastTo Box
                    be@(boolFrame,inj1,ext1) <- boolEditor
                        (paraName <<<- ParaName boolLabel $ emptyParams)
                        notifierBool
                    boxPackStart box boolFrame False False 0
                    containerAdd widget box
                    registerEvent notifierBool Clicked
                        (onClickedHandler widget coreRef childRef cNoti)
                    propagateEvent notifier [notifierBool] MayHaveChanged
                    case mbVal of
                        (False,val) -> do
                            (childWidget,inj2,ext2) <- getChildEditor childRef childEdit childParams cNoti
                            boxPackEnd box childWidget True True 0
                            widgetShowAll childWidget
                            inj1 ( not positive)
                            inj2 val
                            widgetSetSensitive childWidget False
                        (True,val) -> do
                            (childWidget,inj2,ext2) <- getChildEditor childRef childEdit childParams cNoti
                            boxPackEnd box childWidget True True 0
                            widgetShowAll childWidget
                            inj1 positive
                            inj2 val
                            widgetSetSensitive childWidget True
                    writeIORef coreRef (Just (be,box))
                Just (be@(boolFrame,inj1,extt),box) -> do
                    hasChild <- hasChildEditor childRef
                    case mbVal of
                        (False,val) ->
                            if hasChild
                                then do
                                    (childWidget,_,_) <- getChildEditor childRef childEdit childParams cNoti
                                    inj1 (not positive)
                                    widgetSetSensitive childWidget False
                                else inj1 (not positive)
                        (True,val) ->
                            if hasChild
                                then do
                                    inj1 positive
                                    (childWidget,inj2,_) <- getChildEditor childRef childEdit childParams cNoti
                                    inj2 val
                                    widgetSetSensitive childWidget True
                                else do
                                    inj1 positive
                                    (childWidget,inj2,_) <- getChildEditor childRef childEdit childParams cNoti
                                    boxPackEnd box childWidget True True 0
                                    widgetSetSensitive childWidget True
                                    inj2 val)
        (do
            core <- readIORef coreRef
            case core of
                Nothing  -> return Nothing
                Just (be@(boolFrame,inj1,ext1),_) -> do
                    bool <- ext1
                    case bool of
                        Nothing -> return Nothing
                        Just bv | bv == positive -> do
                            (_,_,ext2) <- getChildEditor childRef childEdit childParams cNoti
                            value <- ext2
                            case value of
                                Nothing -> return Nothing
                                Just value -> return (Just (True, value))
                        otherwise -> do
                            (_,_,ext2) <- getChildEditor childRef childEdit childParams cNoti
                            value <- ext2
                            case value of
                                Nothing -> return Nothing
                                Just value -> return (Just (False, value)))
        parameters
        notifier
    where
    onClickedHandler widget coreRef childRef cNoti event = do
        core <- readIORef coreRef
        case core of
            Nothing  -> error "Impossible"
            Just (be@(boolFrame,inj1,ext1),vBox) -> do
                mbBool <- ext1
                case mbBool of
                    Just bool ->
                        if bool /= positive
                            then do

                                hasChild <- hasChildEditor childRef
                                when hasChild $ do
                                    (childWidget,_,_) <- getChildEditor childRef childEdit childParams cNoti
                                    widgetSetSensitive childWidget False
                            else do
                                hasChild <- hasChildEditor childRef
                                if hasChild
                                    then do
                                        (childWidget,_,_) <- getChildEditor childRef childEdit childParams cNoti
                                        widgetSetSensitive childWidget True
                                    else do
                                        (childWidget,inj2,_) <- getChildEditor childRef childEdit childParams cNoti
                                        boxPackEnd vBox childWidget False False 0
                                        inj2 getDefault
                                        widgetSetSensitive childWidget True
                    Nothing -> return ()
                return (event {gtkReturn=True})
    getChildEditor childRef childEditor childParams cNoti =  do
        mb <- readIORef childRef
        case mb of
            Just editor -> return editor
            Nothing -> do
                let val = childEditor
                editor@(_,_,_) <- childEditor childParams cNoti
                mapM_ (propagateEvent notifier [cNoti]) allGUIEvents
                writeIORef childRef (Just editor)
                return editor
    hasChildEditor childRef =  do
        mb <- readIORef childRef
        return (isJust mb)

--
-- | An editor with a subeditor which gets active, when a checkbox is selected
-- or deselected (if the positive Argument is False)
eitherOrEditor :: (Default alpha, Default beta) => (Editor alpha, Parameters) ->
                        (Editor beta, Parameters) -> Text -> Editor (Either alpha beta)
eitherOrEditor (leftEditor,leftParams) (rightEditor,rightParams)
            label2 parameters notifier = do
    coreRef <- newIORef Nothing
    noti1 <- emptyNotifier
    noti2 <- emptyNotifier
    noti3 <- emptyNotifier
    mapM_ (propagateEvent notifier [noti1,noti2,noti3]) allGUIEvents
    be@(boolFrame,inj1,ext1) <- boolEditor2  (getParameter paraName rightParams) leftParams noti1
    le@(leftFrame,inj2,ext2) <- leftEditor (paraName <<<- ParaName "" $ leftParams) noti2
    re@(rightFrame,inj3,ext3) <- rightEditor (paraName <<<- ParaName "" $ rightParams) noti3
    mkEditor
        (\widget v -> do
            core <- readIORef coreRef
            case core of
                Nothing  -> do
                    registerEvent noti1 Clicked (onClickedHandler widget coreRef)
                    box <- case getParameter paraDirection parameters of
                        Horizontal -> hBoxNew False 1 >>= unsafeCastTo Box
                        Vertical   -> vBoxNew False 1 >>= unsafeCastTo Box
                    boxPackStart box boolFrame False False 0
                    containerAdd widget box
                    case v of
                        Left vl -> do
                          boxPackStart box leftFrame False False 0
                          inj2 vl
                          inj3 getDefault
                          inj1 True
                        Right vr  -> do
                          boxPackStart box rightFrame False False 0
                          inj3 vr
                          inj2 getDefault
                          inj1 False
                    writeIORef coreRef (Just (be,le,re,box))
                Just ((_,inj1,_),(leftFrame,inj2,_),(rightFrame,inj3,_),box) ->
                    case v of
                            Left vl -> do
                              containerRemove box rightFrame
                              boxPackStart box leftFrame False False 0
                              inj2 vl
                              inj3 getDefault
                              inj1 True
                            Right vr  -> do
                              containerRemove box leftFrame
                              boxPackStart box rightFrame False False 0
                              inj3 vr
                              inj2 getDefault
                              inj1 False)
        (do core <- readIORef coreRef
            case core of
                Nothing -> return Nothing
                Just ((_,_,ext1),(_,_,ext2),(_,_,ext3),_) -> do
                    mbbool <- ext1
                    case mbbool of
                        Nothing -> return Nothing
                        Just True   ->  do
                            value <- ext2
                            case value of
                                Nothing -> return Nothing
                                Just value -> return (Just (Left value))
                        Just False -> do
                            value <- ext3
                            case value of
                                Nothing -> return Nothing
                                Just value -> return (Just (Right value)))
        (paraName <<<- ParaName "" $ parameters)
        notifier
    where
    onClickedHandler widget coreRef event =  do
        core <- readIORef coreRef
        case core of
            Nothing  -> error "Impossible"
            Just (be@(_,_,ext1),(leftFrame,_,_),(rightFrame,_,_),box) -> do
                mbBool <- ext1
                case mbBool of
                    Just bool ->
                            if bool then do
                              containerRemove box rightFrame
                              boxPackStart box leftFrame False False 0
                              widgetShowAll box
                            else do
                              containerRemove box leftFrame
                              boxPackStart box rightFrame False False 0
                              widgetShowAll box
                    Nothing -> return ()
                return event{gtkReturn=True}


-- a trivial example: (ColumnDescr False [("",(\row -> [cellText := show row]))])
-- and a nontrivial:
--  [("Package",\(Dependency str _) -> [cellText := str])
--  ,("Version",\(Dependency _ vers) -> [cellText := showVersionRange vers])])
data ColumnDescr row = ColumnDescr Bool [(Text, row -> [AttrOp CellRendererText 'AttrSet])]

--
-- | An editor with a subeditor, of which a list of items can be selected
multisetEditor :: (Show alpha, Default alpha, Eq alpha) => ColumnDescr alpha
    -> (Editor alpha, Parameters)
    -> Maybe ([alpha] -> [alpha]) -- ^ The 'mbSort' arg, a sort function if desired
    -> Maybe (alpha -> alpha -> Bool) -- ^ The 'mbReplace' arg, a function which is a criteria for removing an
                              --   old entry when adding a new value
    -> Editor [alpha]
multisetEditor (ColumnDescr showHeaders columnsDD) (singleEditor, sParams) mbSort mbReplace
        parameters notifier = do
    coreRef <- newIORef Nothing
    cnoti   <- emptyNotifier
    mkEditor
        (\widget vs -> do
            core <- readIORef coreRef
            case core of
                Nothing  -> do
                    (box,buttonBox) <- case getParameter paraDirection parameters of
                        Horizontal -> do
                            b  <- hBoxNew False 1 >>= unsafeCastTo Box
                            bb <- vButtonBoxNew >>= unsafeCastTo ButtonBox
                            return (b, bb)
                        Vertical -> do
                            b  <- vBoxNew False 1 >>= unsafeCastTo Box
                            bb <- hButtonBoxNew >>= unsafeCastTo ButtonBox
                            return (b, bb)
                    (frameS,injS,extS) <- singleEditor sParams cnoti
                    mapM_ (propagateEvent notifier [cnoti]) allGUIEvents
                    addButton   <- buttonNewWithLabel "Add"
                    removeButton <- buttonNewWithLabel "Remove"
                    containerAdd buttonBox addButton
                    containerAdd buttonBox removeButton
                    seqStore   <-  seqStoreNew ([]:: [alpha])
                    activateEvent seqStore notifier
                        (Just (\ w h -> afterTreeModelRowInserted w (\ _ _ -> void h))) MayHaveChanged
                    activateEvent seqStore notifier
                        (Just (\ w h -> afterTreeModelRowDeleted w (\ _ -> void h))) MayHaveChanged
                    treeView    <-  treeViewNewWithModel seqStore
                    let minSize =   getParameter paraMinSize parameters
                    uncurry (widgetSetSizeRequest treeView) minSize
                    sw          <-  scrolledWindowNew noAdjustment noAdjustment
                    containerAdd sw treeView
                    scrolledWindowSetPolicy sw PolicyTypeAutomatic PolicyTypeAutomatic
                    scrolledWindowSetMinContentHeight sw (snd minSize)
                    sel         <-  treeViewGetSelection treeView
                    treeSelectionSetMode sel SelectionModeSingle
                    mapM_ (\(str,func) -> do
                            col <- treeViewColumnNew
                            treeViewColumnSetTitle  col str
                            treeViewColumnSetResizable col True
                            treeViewAppendColumn treeView col
                            renderer <- cellRendererTextNew
                            cellLayoutPackStart col renderer True
                            cellLayoutSetAttributes col renderer seqStore func
                        ) columnsDD
                    treeViewSetHeadersVisible treeView showHeaders
                    onTreeSelectionChanged sel $ selectionHandler sel seqStore injS
                    boxPackStart box sw True True 0
                    boxPackStart box buttonBox False False 0
                    boxPackStart box frameS False False 0
                    activateEvent treeView notifier Nothing FocusOut
                    containerAdd widget box
                    seqStoreClear seqStore
                    mapM_ (seqStoreAppend seqStore)
                        (case mbSort of
                            Nothing -> vs
                            Just sortF -> sortF vs)
                    onButtonClicked addButton $ do
                        mbv <- extS
                        case mbv of
                            Just v -> do
                                case mbReplace of
                                    Nothing         -> return ()
                                    Just replaceF   -> do
                                         cont <- seqStoreToList seqStore
                                         mapM_ (seqStoreRemove seqStore . fst)
                                            . filter (\(_,e) -> replaceF v e)
                                                $ zip [0..] cont
                                case mbSort of
                                    Nothing    -> do
                                        seqStoreAppend seqStore v
                                        return ()
                                    Just sortF -> do
                                        cont <- seqStoreToList seqStore
                                        seqStoreClear seqStore
                                        mapM_ (seqStoreAppend seqStore) (sortF (v:cont))
                                cont <- seqStoreToList seqStore
                                case elemIndex v cont of
                                    Just idx -> do
                                        path <- treePathNewFromIndices' [fromIntegral idx]
                                        treeSelectionSelectPath sel path
                                        treeViewScrollToCell treeView (Just path) noTreeViewColumn False 0.0 0.0
                                    Nothing -> return ()
                            Nothing -> return ()
                    onButtonClicked removeButton $ do
                        mbi <- treeSelectionGetSelected sel
                        case mbi of
                            (True, _, iter) -> do
                                [i] <- treeModelGetPath seqStore iter >>= treePathGetIndices
                                seqStoreRemove seqStore i
                            _ -> return ()
                    writeIORef coreRef (Just seqStore)
                    injS getDefault
                Just seqStore -> do
                    seqStoreClear seqStore
                    mapM_ (seqStoreAppend seqStore)
                        (case mbSort of
                            Nothing -> vs
                            Just sortF -> sortF vs))
        (do core <- readIORef coreRef
            case core of
                Nothing -> return Nothing
                Just seqStore -> do
                    v <- seqStoreToList seqStore
                    return (Just v))
        (paraMinSize <<<- ParaMinSize (-1,-1) $ parameters)
        notifier
    where
--    selectionHandler :: TreeSelection -> SeqStore a -> Injector a -> IO ()
    selectionHandler sel seqStore inj = do
        ts <- treeSelectionGetSelected sel
        case ts of
            (True, _, iter) -> do
                [i] <- treeModelGetPath seqStore iter >>= treePathGetIndices
                v <- seqStoreGetValue seqStore i
                inj v
                return ()
            _ -> return ()


filesEditor :: Maybe FilePath -> FileChooserAction -> Text -> Editor [FilePath]
filesEditor fp act label p =
    multisetEditor
        (ColumnDescr False [("", \ row -> [_text := T.pack row])])
        (fileEditor fp act label, emptyParams)
        (Just sort)
        (Just (==))
        (paraShadow <<<- ParaShadow ShadowTypeIn $
            paraDirection  <<<- ParaDirection Vertical $ p)

textsEditor :: (Text -> Bool) -> Bool -> Editor [Text]
textsEditor validation trimBlanks p =
    multisetEditor
        (ColumnDescr False [("", \ row -> [_text := row])])
        (textEditor validation trimBlanks, emptyParams)
        (Just sort)
        (Just (==))
        (paraShadow <<<- ParaShadow ShadowTypeIn $ p)

dependencyEditor :: [PackageIdentifier] -> Editor Dependency
dependencyEditor packages para noti = do
    (wid,inj,ext) <- pairEditor
        (comboEntryEditor ((sort . nub) (map (T.pack . display . pkgName) packages))
            , paraName <<<- ParaName "Select" $ emptyParams)
        (versionRangeEditor,paraName <<<- ParaName "Version" $ emptyParams)
        (paraDirection <<<- ParaDirection Vertical $ para)
        noti
    let pinj (Dependency pn@(PackageName s) v) = inj (T.pack s,v)
    let pext = do
        mbp <- ext
        case mbp of
            Nothing -> return Nothing
            Just ("",v) -> return Nothing
            Just (s,v) -> return (Just $ Dependency (PackageName (T.unpack s)) v)
    return (wid,pinj,pext)

dependenciesEditor :: [PackageIdentifier] -> Editor [Dependency]
dependenciesEditor packages p =
    multisetEditor
        (ColumnDescr True [("Package",\(Dependency (PackageName str) _) -> [_text := T.pack str])
                           ,("Version",\(Dependency _ vers) -> [_text := T.pack $ display vers])])
        (dependencyEditor packages,
            paraOuterAlignment <<<- ParaInnerAlignment (0.0, 0.5, 1.0, 1.0)
                $ paraInnerAlignment <<<- ParaOuterAlignment (0.0, 0.5, 1.0, 1.0)
                   $ emptyParams)
        (Just (sortBy (\ (Dependency p1 _) (Dependency p2 _) -> compare p1 p2)))
        (Just (\ (Dependency p1 _) (Dependency p2 _) -> p1 == p2))
        (paraShadow <<<- ParaShadow ShadowTypeIn
            $ paraOuterAlignment <<<- ParaInnerAlignment (0.0, 0.5, 1.0, 1.0)
                $ paraInnerAlignment <<<- ParaOuterAlignment (0.0, 0.5, 1.0, 1.0)
                    $ paraDirection  <<<-  ParaDirection Vertical
                        $ paraPack <<<- ParaPack PackGrow
                            $ p)

versionRangeEditor :: Editor VersionRange
versionRangeEditor para noti = do
    (wid,inj,ext) <-
        maybeEditor
            (eitherOrEditor
               (pairEditor (comboSelectionEditor v1 (T.pack . show), emptyParams)
                  (versionEditor,
                   paraName <<<- ParaName "Enter Version" $ emptyParams),
                paraDirection <<<- ParaDirection Vertical $
                   paraName <<<- ParaName "Simple" $
                     paraOuterAlignment <<<- ParaOuterAlignment (0.0, 0.0, 0.0, 0.0) $
                       paraOuterPadding <<<- ParaOuterPadding (0, 0, 0, 0) $
                         paraInnerAlignment <<<- ParaInnerAlignment (0.0, 0.0, 0.0, 0.0) $
                           paraInnerPadding <<<- ParaInnerPadding (0, 0, 0, 0) $ emptyParams)
               (tupel3Editor
                  (comboSelectionEditor v2 (T.pack . show), emptyParams)
                  (versionRangeEditor,
                   paraShadow <<<- ParaShadow ShadowTypeIn $ emptyParams)
                  (versionRangeEditor,
                   paraShadow <<<- ParaShadow ShadowTypeIn $ emptyParams),
                paraName <<<- ParaName "Complex" $
                  paraDirection <<<- ParaDirection Vertical $
                    paraOuterAlignment <<<- ParaOuterAlignment (0.0, 0.0, 0.0, 0.0) $
                      paraOuterPadding <<<- ParaOuterPadding (0, 0, 0, 0) $
                        paraInnerAlignment <<<- ParaInnerAlignment (0.0, 0.0, 0.0, 0.0) $
                          paraInnerPadding <<<- ParaInnerPadding (0, 0, 0, 0) $ emptyParams)
               "Select version range",
             emptyParams)
            False "Any Version"
            (paraDirection <<<- ParaDirection Vertical $ para)
            noti
    let vrinj AnyVersion                =   inj Nothing
        vrinj (WildcardVersion v)       =   inj (Just (Left (WildcardVersionS,v)))
        vrinj (ThisVersion v)           =   inj (Just (Left (ThisVersionS,v)))
        vrinj (LaterVersion v)          =   inj (Just (Left (LaterVersionS,v)))
        vrinj (EarlierVersion v)        =   inj (Just (Left (EarlierVersionS,v)))
        vrinj (UnionVersionRanges (ThisVersion v1) (LaterVersion v2)) | v1 == v2
                                        =  inj (Just (Left (ThisOrLaterVersionS,v1)))
        vrinj (UnionVersionRanges (LaterVersion v1) (ThisVersion v2)) | v1 == v2
                                        =  inj (Just (Left (ThisOrLaterVersionS,v1)))
        vrinj (UnionVersionRanges (ThisVersion v1) (EarlierVersion v2)) | v1 == v2
                                        =  inj (Just (Left (ThisOrEarlierVersionS,v1)))
        vrinj (UnionVersionRanges (EarlierVersion v1) (ThisVersion v2)) | v1 == v2
                                        =  inj (Just (Left (ThisOrEarlierVersionS,v1)))
        vrinj (UnionVersionRanges v1 v2)=  inj (Just (Right (UnionVersionRangesS,v1,v2)))
        vrinj (IntersectVersionRanges v1 v2)
                                        =    inj (Just (Right (IntersectVersionRangesS,v1,v2)))
    let vrext = do  mvr <- ext
                    case mvr of
                        Nothing -> return (Just AnyVersion)
                        Just Nothing -> return (Just AnyVersion)
                        Just (Just (Left (ThisVersionS,v)))     -> return (Just (ThisVersion v))
                        Just (Just (Left (WildcardVersionS,v)))     -> return (Just (WildcardVersion v))
                        Just (Just (Left (LaterVersionS,v)))    -> return (Just (LaterVersion v))
                        Just (Just (Left (EarlierVersionS,v)))   -> return (Just (EarlierVersion v))

                        Just (Just (Left (ThisOrLaterVersionS,v)))   -> return (Just (orLaterVersion  v))
                        Just (Just (Left (ThisOrEarlierVersionS,v)))   -> return (Just (orEarlierVersion  v))
                        Just (Just (Right (UnionVersionRangesS,v1,v2)))
                                                        -> return (Just (UnionVersionRanges v1 v2))
                        Just (Just (Right (IntersectVersionRangesS,v1,v2)))
                                                        -> return (Just (IntersectVersionRanges v1 v2))
    return (wid,vrinj,vrext)
        where
            v1 = [ThisVersionS,WildcardVersionS,LaterVersionS,ThisOrLaterVersionS,EarlierVersionS,ThisOrEarlierVersionS]
            v2 = [UnionVersionRangesS,IntersectVersionRangesS]

data Version1 = ThisVersionS | WildcardVersionS | LaterVersionS | ThisOrLaterVersionS | EarlierVersionS | ThisOrEarlierVersionS
    deriving (Eq)
instance Show Version1 where
    show ThisVersionS   =  "This Version"
    show WildcardVersionS   =  "Wildcard Version"
    show LaterVersionS  =  "Later Version"
    show ThisOrLaterVersionS = "This or later Version"
    show EarlierVersionS =  "Earlier Version"
    show ThisOrEarlierVersionS = "This or earlier Version"

data Version2 = UnionVersionRangesS | IntersectVersionRangesS
    deriving (Eq)
instance Show Version2 where
    show UnionVersionRangesS =  "Union Version Ranges"
    show IntersectVersionRangesS =  "Intersect Version Ranges"

versionEditor :: Editor Version
versionEditor para noti = do
    (wid,inj,ext) <- stringEditor (not . null) True para noti
    let pinj v = inj (display v)
    let pext = do
        s <- ext
        case s of
            Nothing -> return Nothing
            Just s -> return (simpleParse s)
    return (wid, pinj, pext)

instance Default Version1
    where getDefault = ThisVersionS

instance Default Version2
    where getDefault = UnionVersionRangesS

instance Default Version
    where getDefault = forceJust (simpleParse "0") "PackageEditor>>default version"

instance Default VersionRange
    where getDefault = AnyVersion

instance Default Dependency
    where getDefault = Dependency getDefault getDefault

instance Default PackageName
    where getDefault = PackageName getDefault






