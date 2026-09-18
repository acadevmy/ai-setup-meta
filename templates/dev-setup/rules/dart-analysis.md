---
paths:
  - "**/analysis_options.yaml"
  - "**/analysis_options.yml"
---

# Dart analyzer configuration

`dart analyze` runs clean — zero **warnings**, not "zero errors". That only holds
if the file below keeps its teeth: relaxing a rule here is how a codebase stops
being analysed, and it is a change that needs a reason in the pull request.

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  language:
    strict-casts: true
    strict-raw-types: true
  errors:
    missing_return: error
    must_be_immutable: error

linter:
  rules:
    avoid_dynamic_calls: true
    avoid_print: true
    prefer_const_constructors: true
    prefer_const_literals_to_create_immutables: true
    prefer_final_fields: true
    prefer_final_locals: true
    always_declare_return_types: true
    unawaited_futures: true
    cancel_subscriptions: true
    always_use_package_imports: true
    use_key_in_widget_constructors: true
    directives_ordering: true
```

Each of these backs a rule stated in prose elsewhere: `strict-casts` and
`avoid_dynamic_calls` are "no `dynamic`", `prefer_const_*` and
`use_key_in_widget_constructors` are the widget rules, `always_use_package_imports`
and `directives_ordering` are the import convention. Removing a line does not
relax a lint — it deletes the only thing enforcing a rule the team agreed on.

`analyzer.exclude` is for generated code (`*.g.dart`, `*.freezed.dart`), never for
a directory somebody would rather not fix.
