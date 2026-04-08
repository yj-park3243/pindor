// GeoJSON 타입 선언 (글로벌)
declare namespace GeoJSON {
  interface Polygon {
    type: 'Polygon';
    coordinates: number[][][];
  }
}
