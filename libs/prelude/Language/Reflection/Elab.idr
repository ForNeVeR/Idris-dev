||| Primitives and tactics for elaborator reflection.
|||
||| Elaborator reflection allows Idris code to control Idris's
||| built-in elaborator, and re-use features like the unifier, the
||| type checker, and the hole mechanism.
module Language.Reflection.Elab

import Builtins
import Prelude.Applicative
import Prelude.Basics
import Prelude.Bool
import Prelude.Functor
import Prelude.List
import Prelude.Maybe
import Prelude.Monad
import Prelude.Nat
import Language.Reflection

data Fixity = Infixl Nat | Infixr Nat | Infix Nat | Prefix Nat

||| Erasure annotations reflect Idris's idea of what is intended to be
||| erased.
data Erasure = Erased | NotErased

||| How an argument is provided in high-level Idris
data Plicity =
  ||| The argument is directly provided at the application site
  Explicit |
  ||| The argument is found by Idris at the application site
  Implicit |
  ||| The argument is solved using interface resolution
  Constraint

||| Function arguments
|||
||| These are the simplest representation of argument lists, and are
||| used for functions. Additionally, because a FunArg provides enough
||| information to build an application, a generic type lookup of a
||| top-level identifier will return its FunArgs, if applicable.
record FunArg where
  constructor MkFunArg
  name    : TTName
  type    : Raw
  plicity : Plicity
  erasure : Erasure

||| Type constructor arguments
|||
||| Each argument is identified as being either a parameter that is
||| consistent in all constructors, or an index that varies based on
||| which constructor is selected.
data TyConArg =
  ||| Parameters are uniform across the constructors
  TyConParameter FunArg |
  ||| Indices are not uniform
  TyConIndex FunArg

||| A type declaration
record TyDecl where
  constructor Declare

  ||| The name of the function being declared.
  name : TTName

  ||| Each argument is in the scope of the names of previous arguments.
  arguments : List FunArg

  ||| The return type is in the scope of all the argument names.
  returnType : Raw


||| A single pattern-matching clause
data FunClause : Type -> Type where
  MkFunClause : (lhs, rhs : a) -> FunClause a
  MkImpossibleClause : (lhs : a) -> FunClause a

||| A reflected function definition.
record FunDefn a where
  constructor DefineFun
  name : TTName
  clauses : List (FunClause a)


data CtorArg = CtorParameter FunArg | CtorField FunArg

||| A reflected datatype definition
record Datatype where
  constructor MkDatatype

  ||| The name of the type constructor
  name : TTName

  ||| The arguments to the type constructor
  tyConArgs : List TyConArg

  ||| The result of the type constructor
  tyConRes : Raw

  ||| The constructors for the family
  constructors : List (TTName, List CtorArg, Raw)

||| A reflected elaboration script.
abstract
data Elab : Type -> Type where
  -- obligatory control stuff
  Prim__PureElab : a -> Elab a
  Prim__BindElab : {a, b : Type} -> Elab a -> (a -> Elab b) -> Elab b

  Prim__Try : {a : Type} -> Elab a -> Elab a -> Elab a
  Prim__Fail : {a : Type} -> List ErrorReportPart -> Elab a

  Prim__Env : Elab (List (TTName, Binder TT))
  Prim__Goal : Elab (TTName, TT)
  Prim__Holes : Elab (List TTName)
  Prim__Guess : Elab TT
  Prim__LookupTy : TTName -> Elab (List (TTName, NameType, TT))
  Prim__LookupDatatype : TTName -> Elab (List Datatype)
  Prim__LookupFunDefn : TTName -> Elab (List (FunDefn TT))
  Prim__LookupArgs : TTName -> Elab (List (TTName, List FunArg, Raw))

  Prim__Check : List (TTName, Binder TT) -> Raw -> Elab (TT, TT)

  Prim__SourceLocation : Elab SourceLocation
  Prim__Namespace : Elab (List String)

  Prim__Gensym : String -> Elab TTName

  Prim__Solve : Elab ()
  Prim__Fill : Raw -> Elab ()
  Prim__Apply : Raw -> List Bool -> Elab (List (TTName, TTName))
  Prim__MatchApply : Raw -> List Bool -> Elab (List (TTName, TTName))
  Prim__Focus : TTName -> Elab ()
  Prim__Unfocus : TTName -> Elab ()
  Prim__Attack : Elab ()

  Prim__Rewrite : Raw -> Elab ()

  Prim__Claim : TTName -> Raw -> Elab ()
  Prim__Intro : Maybe TTName -> Elab ()
  Prim__Forall : TTName -> Raw -> Elab ()
  Prim__PatVar : TTName -> Elab ()
  Prim__PatBind : TTName -> Elab ()
  Prim__LetBind : TTName -> Raw -> Raw -> Elab ()

  Prim__Compute : Elab ()
  Prim__Normalise : (List (TTName, Binder TT)) -> TT -> Elab TT
  Prim__Whnf : TT -> Elab TT
  Prim__Converts : (List (TTName, Binder TT)) -> TT -> TT -> Elab ()

  Prim__DeclareType : TyDecl -> Elab ()
  Prim__DefineFunction : FunDefn Raw -> Elab ()
  Prim__AddInstance : TTName -> TTName -> Elab ()
  Prim__IsTCName : TTName -> Elab Bool

  Prim__ResolveTC : TTName -> Elab ()
  Prim__Search : Int -> List TTName -> Elab ()
  Prim__RecursiveElab : Raw -> Elab () -> Elab (TT, TT)

  Prim__Fixity : String -> Elab Fixity

  Prim__Debug : {a : Type} -> List ErrorReportPart -> Elab a
  Prim__Metavar : TTName -> Elab ()

-------------
-- Public API
-------------
%access public
namespace Tactics
  implementation Functor Elab where
    map f t = Prim__BindElab t (\x => Prim__PureElab (f x))

  implementation Applicative Elab where
    pure x  = Prim__PureElab x
    f <*> x = Prim__BindElab f $ \g =>
              Prim__BindElab x $ \y =>
              Prim__PureElab   $ g y

  ||| The Alternative implementation on Elab represents left-biased error
  ||| handling. In other words, `t <|> t'` will run `t`, and if it
  ||| fails, roll back the elaboration state and run `t'`.
  implementation Alternative Elab where
    empty   = Prim__Fail [TextPart "empty"]
    x <|> y = Prim__Try x y

  implementation Monad Elab where
    x >>= f = Prim__BindElab x f

  ||| Halt elaboration with an error
  fail : List ErrorReportPart -> Elab a
  fail err = Prim__Fail err

  ||| Look up the lexical binding at the focused hole. Fails if no holes are present.
  getEnv : Elab (List (TTName, Binder TT))
  getEnv = Prim__Env

  ||| Get the name and type of the focused hole. Fails if not holes are present.
  getGoal : Elab (TTName, TT)
  getGoal = Prim__Goal

  ||| Get the hole queue, in order.
  getHoles : Elab (List TTName)
  getHoles = Prim__Holes

  ||| If the current hole contains a guess, return it. Otherwise, fail.
  getGuess : Elab TT
  getGuess = Prim__Guess

  ||| Look up the types of every overloading of a name.
  lookupTy :  TTName -> Elab (List (TTName, NameType, TT))
  lookupTy n = Prim__LookupTy n

  ||| Get the type of a fully-qualified name. Fail if it doesn not
  ||| resolve uniquely.
  lookupTyExact : TTName -> Elab (TTName, NameType, TT)
  lookupTyExact n = case !(lookupTy n) of
                      [res] => return res
                      []    => fail [NamePart n, TextPart "is not defined."]
                      xs    => fail [NamePart n, TextPart "is ambiguous."]

  ||| Find the reflected representation of all datatypes whose names
  ||| are overloadings of some name.
  lookupDatatype : TTName -> Elab (List Datatype)
  lookupDatatype n = Prim__LookupDatatype n

  ||| Find the reflected representation of a datatype, given its
  ||| fully-qualified name. Fail if the name does not uniquely resolve
  ||| to a datatype.
  lookupDatatypeExact : TTName -> Elab Datatype
  lookupDatatypeExact n = case !(lookupDatatype n) of
                            [res] => return res
                            []    => fail [TextPart "No datatype named", NamePart n]
                            xs    => fail [TextPart "More than one datatype named", NamePart n]

  ||| Find the reflected function definition of all functions whose names
  ||| are overloadings of some name.
  lookupFunDefn : TTName -> Elab (List (FunDefn TT))
  lookupFunDefn n = Prim__LookupFunDefn n

  ||| Find the reflected function definition of a function, given its
  ||| fully-qualified name. Fail if the name does not uniquely resolve
  ||| to a function.
  lookupFunDefnExact : TTName -> Elab (FunDefn TT)
  lookupFunDefnExact n = case !(lookupFunDefn n) of
                           [res] => return res
                           []    => fail [TextPart "No function named", NamePart n]
                           xs    => fail [TextPart "More than one function named", NamePart n]

  ||| Get the argument specification for each overloading of a name.
  lookupArgs : TTName -> Elab (List (TTName, List FunArg, Raw))
  lookupArgs n = Prim__LookupArgs n

  ||| Get the argument specification for a name. Fail if the name does
  ||| not uniquely resolve.
  lookupArgsExact : TTName -> Elab (TTName, List FunArg, Raw)
  lookupArgsExact n = case !(lookupArgs n) of
                        [res] => return res
                        []    => fail [NamePart n, TextPart "is not defined."]
                        xs    => fail [NamePart n, TextPart "is ambiguous."]

  ||| Attempt to type-check a term, getting back itself and its type.
  |||
  ||| @ env the environment within which to check the type
  ||| @ tm the term to check
  check : (env : List (TTName, Binder TT)) -> (tm : Raw) -> Elab (TT, TT)
  check env tm = Prim__Check env tm


  ||| Generate a unique name based on some hint.
  |||
  ||| **NB**: the generated name is unique _for this run of the
  ||| elaborator_. Do not assume that they are globally unique.
  gensym : (hint : String) -> Elab TTName
  gensym hint = Prim__Gensym hint

  ||| Substitute a guess into a hole.
  solve : Elab ()
  solve = Prim__Solve

  ||| Place a term into a hole, unifying its type. Fails if the focus
  ||| is not a hole.
  fill : Raw -> Elab ()
  fill tm = Prim__Fill tm

  ||| Attempt to apply an operator to fill the current hole,
  ||| potentially solving arguments by unification.
  |||
  ||| The return value is the list of holes established for the
  ||| arguments to the function.
  |||
  ||| Note that not all of the returned hole names still exist, as
  ||| they may have been solved.
  |||
  ||| @ op the term to apply
  |||
  ||| @ argSpec instructions for finding the arguments to the term,
  |||     where the Boolean states whether or not to attempt to solve
  |||     the argument by unification.
  apply : (op : Raw) -> (argSpec : List Bool) -> Elab (List TTName)
  apply tm argSpec = map snd <$> Prim__Apply tm argSpec

  ||| Attempt to apply an operator to fill the current hole,
  ||| potentially solving arguments by matching.
  |||
  ||| The return value is the list of holes established for the
  ||| arguments to the function.
  |||
  ||| Note that not all of the returned hole names still exist, as
  ||| they may have been solved.
  |||
  ||| @ op the term to apply
  |||
  ||| @ argSpec instructions for finding the arguments to the term,
  |||     where the Boolean states whether or not to attempt to solve
  |||     the argument by matching.

  matchApply : (op : Raw) -> (argSpec : List Bool) -> Elab (List TTName)
  matchApply tm argSpec = map snd <$> Prim__Apply tm argSpec

  ||| Move the focus to the specified hole. Fails if the hole does not
  ||| exist.
  |||
  ||| @ hole the hole to focus on
  focus : (hole : TTName) -> Elab ()
  focus hole = Prim__Focus hole

  ||| Send the currently-focused hole to the end of the hole queue and
  ||| focus on the next hole.
  unfocus : TTName -> Elab ()
  unfocus hole = Prim__Unfocus hole

  ||| Convert a hole to make it suitable for bindings - that is,
  ||| transform it such that it has the form `?h : t . h` as opposed to
  ||| `?h : t . f h`.
  |||
  ||| The binding tactics require that a hole be directly under its
  ||| binding, or else the scopes of the generated terms won't make
  ||| sense. This tactic creates a new hole of the proper form, and
  ||| points the old hole at it.
  attack : Elab ()
  attack = Prim__Attack

  ||| Introduce a new hole with a specified name and type.
  |||
  ||| The new hole will be focused, and the previously-focused hole
  ||| will be immediately after it in the hole queue. Because this
  ||| tactic introduces a new binding, you may need to `attack` first.
  claim : TTName -> Raw -> Elab ()
  claim n ty = Prim__Claim n ty

  ||| Introduce a lambda binding around the current hole and focus on
  ||| the body. Requires that the hole be in binding form (use
  ||| `attack`).
  |||
  ||| @ n the name to use for the argument
  intro : (n : TTName) -> Elab ()
  intro n = Prim__Intro (Just n)

  ||| Introduce a lambda binding around the current hole and focus on
  ||| the body, using the name provided by the type of the
  ||| hole.
  |||
  ||| Requires that the hole be immediately under its binder (use
  ||| `attack` if it might not be).
  intro' : Elab ()
  intro' = Prim__Intro Nothing

  ||| Introduce a dependent function type binding into the current hole,
  ||| and focus on the body.
  |||
  ||| Requires that the hole be immediately under its binder (use
  ||| `attack` if it might not be).
  forall : TTName -> Raw -> Elab ()
  forall n ty = Prim__Forall n ty

  ||| Convert a hole into a pattern variable.
  patvar : TTName -> Elab ()
  patvar n = Prim__PatVar n

  ||| Introduce a new pattern binding.
  |||
  ||| Requires that the hole be immediately under its binder (use
  ||| `attack` if it might not be).
  patbind : TTName -> Elab ()
  patbind n = Prim__PatBind n

  ||| Introduce a new let binding.
  |||
  ||| Requires that the hole be immediately under its binder (use
  ||| `attack` if it might not be).
  |||
  ||| @ n the name to let bind
  ||| @ ty the type of the term to be let-bound
  ||| @ tm the term to be bound
  letbind : (n : TTName) -> (ty, tm : Raw) -> Elab ()
  letbind n ty tm = Prim__LetBind n ty tm

  ||| Normalise the goal.
  compute : Elab ()
  compute = Prim__Compute

  ||| Normalise a term in some lexical environment
  |||
  ||| @ env the environment in which to compute (get one of these from `getEnv`)
  ||| @ term the term to normalise
  normalise : (env : List (TTName, Binder TT)) -> (term : TT) -> Elab TT
  normalise env term = Prim__Normalise env term

  ||| Reduce a closed term to weak-head normal form
  |||
  ||| @ term the term to reduce
  whnf : (term : TT) -> Elab TT
  whnf term = Prim__Whnf term

  ||| Check that two terms are convertable in the current context and
  ||| in some environment.
  |||
  ||| @ env a lexical environment to compare the terms in (see `getEnv`)
  ||| @ term1 the first term to convert
  ||| @ term2 the second term to convert
  convertsInEnv : (env : List (TTName, Binder TT)) -> (term1, term2 : TT) -> Elab ()
  convertsInEnv env term1 term2 = Prim__Converts env term1 term2

  ||| Check that two terms are convertable in the current context and environment
  |||
  ||| @ term1 the first term to convert
  ||| @ term2 the second term to convert
  converts : (term1, term2 : TT) -> Elab ()
  converts term1 term2 = convertsInEnv !getEnv term1 term2

  ||| Find the source context for the elaboration script
  getSourceLocation : Elab SourceLocation
  getSourceLocation = Prim__SourceLocation

  ||| Attempt to solve the current goal with the source code location
  sourceLocation : Elab ()
  sourceLocation = do loc <- getSourceLocation
                      fill (quote loc)
                      solve

  ||| Get the current namespace at the point of tactic execution. This
  ||| allows scripts to define top-level names conveniently.
  |||
  ||| The namespace is represented as a reverse-order list of strings,
  ||| just as in the representation of names.
  currentNamespace : Elab (List String)
  currentNamespace = Prim__Namespace

  ||| Attempt to rewrite the goal using an equality.
  |||
  ||| The tactic searches the goal for applicable subterms, and
  ||| constructs a context for `replace` using them. In some cases,
  ||| this is not possible, and `replace` must be called manually with
  ||| an appropriate context.
  |||
  ||| Because this tactic internally introduces a `let` binding, it
  ||| requires that the hole be immediately under its binder (use
  ||| `attack` if it might not be).
  rewriteWith : Raw -> Elab ()
  rewriteWith rule = Prim__Rewrite rule

  ||| Add a type declaration to the global context.
  declareType : TyDecl -> Elab ()
  declareType decl = Prim__DeclareType decl

  ||| Define a function in the global context. The function must have
  ||| already been declared, either in ordinary Idris code or using
  ||| `declareType`.
  defineFunction : FunDefn Raw -> Elab ()
  defineFunction defun = Prim__DefineFunction defun

  ||| Register a new implementation for interface resolution.
  |||
  ||| @ ifaceName the name of the interface for which an implementation is being registered
  ||| @ instName the name of the definition to use in implementation search
  addInstance : (ifaceName, instName : TTName) -> Elab ()
  addInstance ifaceName instName = Prim__AddInstance ifaceName instName

  ||| Determine whether a name denotes an interface.
  |||
  ||| @ name a name that might denote an interface.
  isTCName : (name : TTName) -> Elab Bool
  isTCName name = Prim__IsTCName name

  ||| Attempt to solve the current goal with an interface dictionary
  |||
  ||| @ fn the name of the definition being elaborated (to prevent Idris
  ||| from looping)
  resolveTC : (fn : TTName) -> Elab ()
  resolveTC fn = Prim__ResolveTC fn

  ||| Use Idris's internal proof search.
  search : Elab ()
  search = Prim__Search 100 []

  ||| Use Idris's internal proof search, with more control.
  |||
  ||| @ depth the search depth
  ||| @ hints additional names to try
  search' : (depth : Int) -> (hints : List TTName) -> Elab ()
  search' depth hints = Prim__Search depth hints

  ||| Look up the declared fixity for an operator.
  |||
  ||| The lookup fails if the operator does not yet have a fixity or
  ||| if the string is not a valid operator.
  |||
  ||| @ operator the operator string to look up
  operatorFixity : (operator : String) -> Elab Fixity
  operatorFixity operator = Prim__Fixity operator

  ||| Halt elaboration, dumping the internal state for inspection.
  |||
  ||| This is intended for elaboration script developers, not for
  ||| end-users. Use `fail` for final scripts.
  debug : Elab a
  debug = Prim__Debug []

  ||| Halt elaboration, dumping the internal state and displaying a
  ||| message.
  |||
  ||| This is intended for elaboration script developers, not for
  ||| end-users. Use `fail` for final scripts.
  |||
  ||| @ msg the message to display
  debugMessage : (msg : List ErrorReportPart) -> Elab a
  debugMessage msg = Prim__Debug msg

  ||| Create a new top-level metavariable to solve the current hole.
  |||
  ||| @ name the name for the top-level variable
  metavar : (name : TTName) -> Elab ()
  metavar name = Prim__Metavar name

  ||| Recursively invoke the reflected elaborator with some goal.
  |||
  ||| The result is the final term and its type.
  runElab : Raw -> Elab () -> Elab (TT, TT)
  runElab goal script = Prim__RecursiveElab goal script

