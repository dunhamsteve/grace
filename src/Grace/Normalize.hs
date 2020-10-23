-- | This module contains the logic for efficiently evaluating an expression
module Grace.Normalize
    ( -- * Normalization
      evaluate
    , fresh
    , lookupVariable
    , instantiate
    , normalize
    , quote
    ) where

import Data.Text (Text)
import Grace.Value (Closure(..), Value)
import Grace.Syntax (Syntax)

import qualified Grace.Value  as Value
import qualified Grace.Syntax as Syntax

-- | Lookup a variable from an environment using the variable's name and index
lookupVariable
    :: Text
    -- ^ Variable name
    -> Int
    -- ^ Variable index
    -> [(Text, Value)]
    -- ^ Evaluation environment
    -> Value
lookupVariable name index environment =
    case environment of
        (key, value) : rest ->
            if name == key
            then if index == 0
                 then value
                 else lookupVariable name (index - 1) rest
            else lookupVariable name index rest
        [] ->
            -- In the `Value` type, free variables are stored using negative
            -- indices (starting at -1) to avoid collision with bound variables
            --
            -- >>> evaluate [] "x"
            -- Variable "x" (-1)
            --
            -- This has the nice property that `quote` does the right thing when
            -- converting back to the `Syntax` type.
            Value.Variable name (negate index - 1)

{-| Substitute an expression into a `Closure`

    > instantiate (Closure name env expression) value =
    >    evaluate ((name, value) : env) expression
-}
instantiate :: Closure -> Value -> Value
instantiate (Closure name env syntax) value =
    evaluate ((name, value) : env) syntax

{-| Evaluate an expression, leaving behind a `Value` free of reducible
    sub-expressions

    This function uses separate types for the input (i.e. `Syntax`) and the
    output (i.e. `Value`) in order to avoid wastefully evaluating the same
    sub-expression multiple times.
-}
evaluate
    :: [(Text, Value)]
    -- ^ Evaluation environment (starting at @[]@ for a top-level expression)
    -> Syntax
    -- ^ Surface syntax
    -> Value
    -- ^ Result, free of reducible sub-expressions
evaluate env syntax =
    case syntax of
        Syntax.Variable name index ->
            lookupVariable name index env

        Syntax.Application function argument ->
            case function' of
                Value.Lambda _ (Closure name capturedEnv body) ->
                    evaluate ((name, argument') : capturedEnv) body
                _ ->
                    Value.Application function' argument'
          where
            function' = evaluate env function

            argument' = evaluate env argument

        Syntax.Lambda name inputType body ->
            Value.Lambda (evaluate env inputType) (Closure name env body)

        Syntax.Forall name inputType outputType ->
            Value.Forall (evaluate env inputType) (Closure name env outputType)

        Syntax.Let name _ assignment body ->
            evaluate ((name, evaluate env assignment) : env) body

        Syntax.If predicate ifTrue ifFalse ->
            case predicate' of
                Value.True  -> ifTrue'
                Value.False -> ifFalse'
                _           -> Value.If predicate' ifTrue' ifFalse'
          where
            predicate' = evaluate env predicate

            ifTrue' = evaluate env ifTrue

            ifFalse' = evaluate env ifFalse

        Syntax.Annotation body _ ->
            evaluate env body

        Syntax.And left right ->
            case left' of
                Value.True -> right'
                Value.False -> Value.False
                _ -> case right' of
                    Value.True -> left'
                    Value.False -> Value.False
                    _ -> Value.And left' right'
          where
            left' = evaluate env left

            right' = evaluate env right

        Syntax.Or left right ->
            case left' of
                Value.True -> Value.True
                Value.False -> right'
                _ -> case right' of
                    Value.True -> Value.True
                    Value.False -> left'
                    _ -> Value.Or left' right'
          where
            left' = evaluate env left

            right' = evaluate env right

        Syntax.Bool ->
            Value.Bool

        Syntax.True ->
            Value.True

        Syntax.False ->
            Value.False

        Syntax.Type ->
            Value.Type

        Syntax.Kind ->
            Value.Kind

countNames :: Text -> [Text] -> Int
countNames name = length . filter (== name)

-- | Obtain a unique variable, given a list of variable names currently in scope
fresh
    :: Text
    -- ^ Variable base name (without the index)
    -> [Text]
    -- ^ Variables currently in scope
    -> Value
    -- ^ Unique variable (including the index)
fresh name names = Value.Variable name (countNames name names)

-- | Convert a `Value` back into the surface `Syntax`
quote
    :: [Text]
    -- ^ Variable names currently in scope (starting at @[]@ for a top-level
    --   expression)
    -> Value
    -> Syntax
quote names value =
    case value of
        Value.Variable name index ->
            Syntax.Variable name (countNames name names - index - 1)

        Value.Lambda inputType closure@(Closure name _ _) ->
            Syntax.Lambda name (quote names inputType) body
          where
            variable = fresh name names

            body = quote (name : names) (instantiate closure variable)

        Value.Forall inputType closure@(Closure name _ _) ->
            Syntax.Forall name (quote names inputType) outputType
          where
            variable = fresh name names

            outputType =
                quote (name : names) (instantiate closure variable)

        Value.Application function argument ->
            Syntax.Application (quote names function) (quote names argument)

        Value.If predicate ifTrue ifFalse ->
            Syntax.If
                (quote names predicate)
                (quote names ifTrue)
                (quote names ifFalse)

        Value.And left right ->
            Syntax.And (quote names left) (quote names right)

        Value.Or left right ->
            Syntax.Or (quote names left) (quote names right)

        Value.Bool ->
            Syntax.Bool

        Value.True ->
            Syntax.True

        Value.False ->
            Syntax.False

        Value.Type ->
            Syntax.Type

        Value.Kind ->
            Syntax.Kind

{-| Evaluate an expression

    This is a convenient wrapper around `evaluate` and `quote` in order to
    evaluate a top-level expression
-}
normalize :: Syntax -> Syntax
normalize = quote [] . evaluate []
