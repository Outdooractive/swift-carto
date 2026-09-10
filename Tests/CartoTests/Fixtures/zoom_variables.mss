@zoom_min: 6;
@zoom_eq: 9;

#world[zoom > @zoom_min] { marker-width: 1; }
#world[zoom = @zoom_eq] { marker-height: 2; }
