forall (f : Type) . forall (e : Type) . forall (d : Type) . forall (c : Fields) . forall (b : Type) . forall (a : Type) . { or : Bool -> Bool -> Bool, and : Bool -> Bool -> Bool, apply : (e -> f) -> e -> f, field : { foo : d, c } -> d, _if : Bool -> b -> b -> b, times : Natural -> Natural -> Natural, plus : Natural -> Natural -> Natural, append : Text -> Text -> Text, fold : Natural -> (a -> a) -> a -> a }