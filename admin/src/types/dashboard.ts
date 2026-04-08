export interface TimeSeriesData {
  date: string;
  value: number;
}

export interface GeoHeatmapData {
  points: {
    lat: number;
    lng: number;
    intensity: number;
    label: string;
  }[];
}

export interface HistogramBucket {
  rangeStart: number;
  rangeEnd: number;
  count: number;
}

export interface HistogramData {
  buckets: HistogramBucket[];
}

export interface DashboardMetrics {
  realtime: {
    activeUsers: number;
    activeMatchRequests: number;
    ongoingMatches: number;
    pendingResultVerifications: number;
  };
  today: {
    newSignups: number;
    matchesCreated: number;
    matchesCompleted: number;
    reportsReceived: number;
  };
  charts: {
    dauTrend: TimeSeriesData[];
    matchSuccessRate: number;
    regionHeatmap: GeoHeatmapData;
    scoreDistribution: HistogramData;
  };
}
