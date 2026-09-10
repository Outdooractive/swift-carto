#world {
  line-color: hsluv(262.9, 1, 0.75);
  line-width: 1;
  polygon-fill: lightenp(#336699, 10);
  polygon-opacity: 0.8;
  [zoom >= 5] {
    marker-fill: spinp(#336699, 45);
    marker-line-color: greyscalep(#336699);
  }
}
