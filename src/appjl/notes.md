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
2. what needs code in Julia
