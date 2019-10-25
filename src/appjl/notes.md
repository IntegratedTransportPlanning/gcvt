# Stuff to replicate from `mb.js`

```
hideLayer({ layer }) {
showLayer({ layer }) {
setVisible({ layer, data }) {
setColor({ layer, color, selected = [] }) {
setWeight({ layer, weight, wFalloff = 4, oFalloff = 5 }) {
setCentroidLines({ lines = [] }) {
setPopup ({text, lng, lat}) {
setHover({coordinates, layer, feature}) {
setHoverData({layer, hints}) {
```

Julia <- GET -> JavaScript on client

Need to decide:
1. what could be handled totally client-side
    - JS uses URL as interface / updates URL as it changes
    - asks Julia for data it needs via GET
2. what needs code in Julia
    - time graphs
        - need to find a decent svg / png plotting library (plotly?)
    - serving "static" site (js) under /map/ route

# Colour palette

- colourbrewer names
- or: array `[[#hex, level], [#hex, level], ...]]` with interpolate true/false
