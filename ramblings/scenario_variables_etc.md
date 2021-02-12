# Scenario / variables / other filters etc

At the moment we have scenarios and years hard-coded as things that can change the output on the map. We want to generalise this.

I'm struggling to think of a decent name for this ... manifesto, but I'm going formalise what we're doing when we're painting pretty colours on the map a little bit. Heckling is requested and desired.

# What is a model / survey data?

I'm going to be lazy and pretend that predictions and observations are the same (which philosophically makes sense to me - observations are a guess at ground truth). So I'll call them all models.

What is a model? It maps a series of independent variables (things you can change) to dependent variables (things you measure or predict).

```
model_[dependent_variable](independent_variables...) = {zoneID => some number}
```

So, for example,

```
model_kgco2perKM(scenario="the-squirrels-fight-back", year=1862, transportMode="jetpack", passengerAges="18-27") = {... => 9001}
```

Our key assumption is that each model has consistent units (i.e. different sets of criteria are directly comparable for the same dependent variable). We also assume that addition makes sense for all outputs.

# How does this map to CSVs?

Each CSV column (aside from the origin and destination zone IDs) corresponds to one set of `dependent_variable-independent_variables...`. Using the example from above:

```
model_kgco2perKM(scenario="the-squirrels-fight-back", year=1862, transportMode="jetpack", passengerAges="18-27") = {... => 9001}

# corresponds to the column name
kgco2perKM_the-squirrels-fight-back_1862_jetpack_18-27
```

Open question: how do we deal with missing independent variables? i.e. holes in the domain of the model? E.g. `scenario=millenium_bug` may not have `passengerAges`.

Suggestion: if we want to support this, use a simple `key=value` format for column names, e.g. `kgco2perKM_scenario=the-squirrels-fight-back_transportMode=jetpack_...`.

# How do we pick these in the web app?

"variable" (the dependent one) is the only thing we are certain will exist for every project, so it should probably go at the top as the first filter.

Then each independent variable is listed below as a filter with a drop-down menu for each. If "compare" is ticked, another panel appears with little "chain link" icons to allow us to link/unlink independent variables for criteria.

For simplicity, values will be sorted alphanumerically in the drop-down menu to deal with categorical and continuous variables comfortably.


Sketch of UI:

```
# Complex model: Festival of Britain 2020

## Criteria available from CSV:
Variable: [CO2 per KM, Energy usage, PM2.5 per KM, Passenger hours]
Scenario: [David Miliband never went to America, Diesel cars are outlawed, Personal transportation is outlawed, Tesla grows into its valuation]
Year: [1990, 1995, 2018, 2023]
Transport mode: [All, Hovercraft, Bicycle, Foot]

## UI:
Variable: CO2 per KM

[compare mode: [x]]
Current | Base [swap]
Scenario: Miliband | Tesla [unlink: [x]]
Year: 2020 | 2020 [unlink: [ ]]
Transport mode: Hovercraft | Hovercraft [unlink: [ ]]

---

# Simple model: Local school transport survey

## Criteria available:
Variable: [Passenger hours]
Transport mode: [SUV, Bicycle, Foot]

## UI:
Variable: Passenger hours

[compare mode: [x]]
Current | Base [swap]
Transport mode: Bicycle | SUV [unlink: [x]]

## UI with comparison disabled:
Variable: Passenger hours

[compare mode: [ ]]
Transport mode: Bicycle
```


# Future potential extensions

We could have a special tag for continuous independent variables to allow them to be binned or averaged. I think this is probably outside the scope of the current project; we should see whether there is demand for that feature first.
