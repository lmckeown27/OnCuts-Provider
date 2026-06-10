/**
 * US Universities Database
 * 
 * Comprehensive list of US universities with coordinates.
 * Used for location-based barber matching.
 * 
 * Data includes major universities, state schools, and colleges.
 * Coordinates are approximate campus center points.
 */

export interface University {
  id: string;
  name: string;
  city: string;
  state: string;
  latitude: number;
  longitude: number;
  shortName?: string; // Common abbreviation (e.g., "UCLA", "MIT")
}

// Comprehensive list of US universities
// Sorted alphabetically by name
export const US_UNIVERSITIES: University[] = [
  // A
  { id: "abilene-christian", name: "Abilene Christian University", city: "Abilene", state: "TX", latitude: 32.4621, longitude: -99.7125 },
  { id: "air-force", name: "United States Air Force Academy", city: "Colorado Springs", state: "CO", latitude: 38.9983, longitude: -104.8614, shortName: "Air Force" },
  { id: "akron", name: "University of Akron", city: "Akron", state: "OH", latitude: 41.0765, longitude: -81.5116 },
  { id: "alabama", name: "University of Alabama", city: "Tuscaloosa", state: "AL", latitude: 33.2140, longitude: -87.5391, shortName: "Alabama" },
  { id: "alabama-birmingham", name: "University of Alabama at Birmingham", city: "Birmingham", state: "AL", latitude: 33.5021, longitude: -86.8086, shortName: "UAB" },
  { id: "alabama-huntsville", name: "University of Alabama in Huntsville", city: "Huntsville", state: "AL", latitude: 34.7254, longitude: -86.6394, shortName: "UAH" },
  { id: "alabama-state", name: "Alabama State University", city: "Montgomery", state: "AL", latitude: 32.3644, longitude: -86.2956 },
  { id: "albany", name: "University at Albany, SUNY", city: "Albany", state: "NY", latitude: 42.6866, longitude: -73.8237 },
  { id: "american", name: "American University", city: "Washington", state: "DC", latitude: 38.9377, longitude: -77.0880 },
  { id: "amherst", name: "Amherst College", city: "Amherst", state: "MA", latitude: 42.3709, longitude: -72.5170 },
  { id: "appalachian-state", name: "Appalachian State University", city: "Boone", state: "NC", latitude: 36.2137, longitude: -81.6746 },
  { id: "arizona", name: "University of Arizona", city: "Tucson", state: "AZ", latitude: 32.2319, longitude: -110.9501, shortName: "Arizona" },
  { id: "arizona-state", name: "Arizona State University", city: "Tempe", state: "AZ", latitude: 33.4242, longitude: -111.9281, shortName: "ASU" },
  { id: "arkansas", name: "University of Arkansas", city: "Fayetteville", state: "AR", latitude: 36.0686, longitude: -94.1748, shortName: "Arkansas" },
  { id: "army", name: "United States Military Academy", city: "West Point", state: "NY", latitude: 41.3915, longitude: -73.9565, shortName: "Army" },
  { id: "auburn", name: "Auburn University", city: "Auburn", state: "AL", latitude: 32.6034, longitude: -85.4808, shortName: "Auburn" },
  
  // B
  { id: "ball-state", name: "Ball State University", city: "Muncie", state: "IN", latitude: 40.2058, longitude: -85.4089 },
  { id: "baylor", name: "Baylor University", city: "Waco", state: "TX", latitude: 31.5489, longitude: -97.1131, shortName: "Baylor" },
  { id: "binghamton", name: "Binghamton University", city: "Binghamton", state: "NY", latitude: 42.0897, longitude: -75.9694 },
  { id: "boise-state", name: "Boise State University", city: "Boise", state: "ID", latitude: 43.6030, longitude: -116.2030 },
  { id: "boston-college", name: "Boston College", city: "Chestnut Hill", state: "MA", latitude: 42.3355, longitude: -71.1685, shortName: "BC" },
  { id: "boston-university", name: "Boston University", city: "Boston", state: "MA", latitude: 42.3505, longitude: -71.1054, shortName: "BU" },
  { id: "bowling-green", name: "Bowling Green State University", city: "Bowling Green", state: "OH", latitude: 41.3787, longitude: -83.6495 },
  { id: "brandeis", name: "Brandeis University", city: "Waltham", state: "MA", latitude: 42.3659, longitude: -71.2594 },
  { id: "brigham-young", name: "Brigham Young University", city: "Provo", state: "UT", latitude: 40.2519, longitude: -111.6493, shortName: "BYU" },
  { id: "brown", name: "Brown University", city: "Providence", state: "RI", latitude: 41.8268, longitude: -71.4025, shortName: "Brown" },
  { id: "buffalo", name: "University at Buffalo", city: "Buffalo", state: "NY", latitude: 43.0008, longitude: -78.7890 },
  { id: "butler", name: "Butler University", city: "Indianapolis", state: "IN", latitude: 39.8407, longitude: -86.1698 },
  
  // C
  { id: "cal-poly", name: "California Polytechnic State University", city: "San Luis Obispo", state: "CA", latitude: 35.3050, longitude: -120.6625, shortName: "Cal Poly SLO" },
  { id: "cal-poly-pomona", name: "California State Polytechnic University, Pomona", city: "Pomona", state: "CA", latitude: 34.0565, longitude: -117.8215, shortName: "Cal Poly Pomona" },
  { id: "cal-state-fullerton", name: "California State University, Fullerton", city: "Fullerton", state: "CA", latitude: 33.8829, longitude: -117.8869, shortName: "CSUF" },
  { id: "cal-state-la", name: "California State University, Los Angeles", city: "Los Angeles", state: "CA", latitude: 34.0664, longitude: -118.1684, shortName: "Cal State LA" },
  { id: "cal-state-long-beach", name: "California State University, Long Beach", city: "Long Beach", state: "CA", latitude: 33.7838, longitude: -118.1141, shortName: "CSULB" },
  { id: "cal-state-northridge", name: "California State University, Northridge", city: "Northridge", state: "CA", latitude: 34.2401, longitude: -118.5298, shortName: "CSUN" },
  { id: "caltech", name: "California Institute of Technology", city: "Pasadena", state: "CA", latitude: 34.1377, longitude: -118.1253, shortName: "Caltech" },
  { id: "carnegie-mellon", name: "Carnegie Mellon University", city: "Pittsburgh", state: "PA", latitude: 40.4433, longitude: -79.9436, shortName: "CMU" },
  { id: "case-western", name: "Case Western Reserve University", city: "Cleveland", state: "OH", latitude: 41.5045, longitude: -81.6089, shortName: "Case Western" },
  { id: "central-florida", name: "University of Central Florida", city: "Orlando", state: "FL", latitude: 28.6024, longitude: -81.2001, shortName: "UCF" },
  { id: "central-michigan", name: "Central Michigan University", city: "Mount Pleasant", state: "MI", latitude: 43.5892, longitude: -84.7697 },
  { id: "charleston", name: "College of Charleston", city: "Charleston", state: "SC", latitude: 32.7841, longitude: -79.9372 },
  { id: "cincinnati", name: "University of Cincinnati", city: "Cincinnati", state: "OH", latitude: 39.1329, longitude: -84.5150, shortName: "Cincinnati" },
  { id: "clemson", name: "Clemson University", city: "Clemson", state: "SC", latitude: 34.6765, longitude: -82.8374, shortName: "Clemson" },
  { id: "coastal-carolina", name: "Coastal Carolina University", city: "Conway", state: "SC", latitude: 33.7946, longitude: -79.0186 },
  { id: "colorado", name: "University of Colorado Boulder", city: "Boulder", state: "CO", latitude: 40.0076, longitude: -105.2659, shortName: "CU Boulder" },
  { id: "colorado-state", name: "Colorado State University", city: "Fort Collins", state: "CO", latitude: 40.5734, longitude: -105.0865, shortName: "CSU" },
  { id: "columbia", name: "Columbia University", city: "New York", state: "NY", latitude: 40.8075, longitude: -73.9626, shortName: "Columbia" },
  { id: "connecticut", name: "University of Connecticut", city: "Storrs", state: "CT", latitude: 41.8077, longitude: -72.2540, shortName: "UConn" },
  { id: "cornell", name: "Cornell University", city: "Ithaca", state: "NY", latitude: 42.4534, longitude: -76.4735, shortName: "Cornell" },
  { id: "creighton", name: "Creighton University", city: "Omaha", state: "NE", latitude: 41.2655, longitude: -95.9455 },
  
  // D
  { id: "dartmouth", name: "Dartmouth College", city: "Hanover", state: "NH", latitude: 43.7044, longitude: -72.2887, shortName: "Dartmouth" },
  { id: "dayton", name: "University of Dayton", city: "Dayton", state: "OH", latitude: 39.7403, longitude: -84.1796 },
  { id: "delaware", name: "University of Delaware", city: "Newark", state: "DE", latitude: 39.6780, longitude: -75.7506, shortName: "Delaware" },
  { id: "denver", name: "University of Denver", city: "Denver", state: "CO", latitude: 39.6780, longitude: -104.9614 },
  { id: "depaul", name: "DePaul University", city: "Chicago", state: "IL", latitude: 41.9253, longitude: -87.6558 },
  { id: "drake", name: "Drake University", city: "Des Moines", state: "IA", latitude: 41.6043, longitude: -93.6562 },
  { id: "drexel", name: "Drexel University", city: "Philadelphia", state: "PA", latitude: 39.9566, longitude: -75.1899 },
  { id: "duke", name: "Duke University", city: "Durham", state: "NC", latitude: 36.0014, longitude: -78.9382, shortName: "Duke" },
  { id: "duquesne", name: "Duquesne University", city: "Pittsburgh", state: "PA", latitude: 40.4365, longitude: -79.9930 },
  
  // E
  { id: "east-carolina", name: "East Carolina University", city: "Greenville", state: "NC", latitude: 35.6076, longitude: -77.3661, shortName: "ECU" },
  { id: "eastern-michigan", name: "Eastern Michigan University", city: "Ypsilanti", state: "MI", latitude: 42.2505, longitude: -83.6238 },
  { id: "emory", name: "Emory University", city: "Atlanta", state: "GA", latitude: 33.7925, longitude: -84.3235, shortName: "Emory" },
  
  // F
  { id: "fau", name: "Florida Atlantic University", city: "Boca Raton", state: "FL", latitude: 26.3729, longitude: -80.1014, shortName: "FAU" },
  { id: "fiu", name: "Florida International University", city: "Miami", state: "FL", latitude: 25.7563, longitude: -80.3748, shortName: "FIU" },
  { id: "florida", name: "University of Florida", city: "Gainesville", state: "FL", latitude: 29.6436, longitude: -82.3549, shortName: "UF" },
  { id: "florida-state", name: "Florida State University", city: "Tallahassee", state: "FL", latitude: 30.4419, longitude: -84.2985, shortName: "FSU" },
  { id: "fordham", name: "Fordham University", city: "Bronx", state: "NY", latitude: 40.8615, longitude: -73.8854 },
  { id: "fresno-state", name: "California State University, Fresno", city: "Fresno", state: "CA", latitude: 36.8134, longitude: -119.7485, shortName: "Fresno State" },
  
  // G
  { id: "george-mason", name: "George Mason University", city: "Fairfax", state: "VA", latitude: 38.8316, longitude: -77.3081, shortName: "GMU" },
  { id: "george-washington", name: "George Washington University", city: "Washington", state: "DC", latitude: 38.8997, longitude: -77.0486, shortName: "GW" },
  { id: "georgetown", name: "Georgetown University", city: "Washington", state: "DC", latitude: 38.9076, longitude: -77.0723, shortName: "Georgetown" },
  { id: "georgia", name: "University of Georgia", city: "Athens", state: "GA", latitude: 33.9480, longitude: -83.3773, shortName: "UGA" },
  { id: "georgia-southern", name: "Georgia Southern University", city: "Statesboro", state: "GA", latitude: 32.4221, longitude: -81.7837 },
  { id: "georgia-state", name: "Georgia State University", city: "Atlanta", state: "GA", latitude: 33.7530, longitude: -84.3853 },
  { id: "georgia-tech", name: "Georgia Institute of Technology", city: "Atlanta", state: "GA", latitude: 33.7756, longitude: -84.3963, shortName: "Georgia Tech" },
  { id: "gonzaga", name: "Gonzaga University", city: "Spokane", state: "WA", latitude: 47.6669, longitude: -117.4022 },
  
  // H
  { id: "harvard", name: "Harvard University", city: "Cambridge", state: "MA", latitude: 42.3770, longitude: -71.1167, shortName: "Harvard" },
  { id: "hawaii", name: "University of Hawaii at Manoa", city: "Honolulu", state: "HI", latitude: 21.2969, longitude: -157.8171, shortName: "Hawaii" },
  { id: "hofstra", name: "Hofstra University", city: "Hempstead", state: "NY", latitude: 40.7140, longitude: -73.6007 },
  { id: "holy-cross", name: "College of the Holy Cross", city: "Worcester", state: "MA", latitude: 42.2377, longitude: -71.8083 },
  { id: "houston", name: "University of Houston", city: "Houston", state: "TX", latitude: 29.7199, longitude: -95.3422, shortName: "Houston" },
  { id: "howard", name: "Howard University", city: "Washington", state: "DC", latitude: 38.9225, longitude: -77.0197 },
  
  // I
  { id: "idaho", name: "University of Idaho", city: "Moscow", state: "ID", latitude: 46.7257, longitude: -117.0134 },
  { id: "illinois", name: "University of Illinois Urbana-Champaign", city: "Champaign", state: "IL", latitude: 40.1020, longitude: -88.2272, shortName: "UIUC" },
  { id: "illinois-chicago", name: "University of Illinois Chicago", city: "Chicago", state: "IL", latitude: 41.8719, longitude: -87.6489, shortName: "UIC" },
  { id: "illinois-state", name: "Illinois State University", city: "Normal", state: "IL", latitude: 40.5106, longitude: -88.9985 },
  { id: "indiana", name: "Indiana University Bloomington", city: "Bloomington", state: "IN", latitude: 39.1653, longitude: -86.5264, shortName: "IU" },
  { id: "indiana-state", name: "Indiana State University", city: "Terre Haute", state: "IN", latitude: 39.4700, longitude: -87.4098 },
  { id: "iowa", name: "University of Iowa", city: "Iowa City", state: "IA", latitude: 41.6611, longitude: -91.5302, shortName: "Iowa" },
  { id: "iowa-state", name: "Iowa State University", city: "Ames", state: "IA", latitude: 42.0267, longitude: -93.6465, shortName: "Iowa State" },
  
  // J
  { id: "james-madison", name: "James Madison University", city: "Harrisonburg", state: "VA", latitude: 38.4382, longitude: -78.8753, shortName: "JMU" },
  { id: "johns-hopkins", name: "Johns Hopkins University", city: "Baltimore", state: "MD", latitude: 39.3299, longitude: -76.6205, shortName: "JHU" },
  
  // K
  { id: "kansas", name: "University of Kansas", city: "Lawrence", state: "KS", latitude: 38.9543, longitude: -95.2558, shortName: "Kansas" },
  { id: "kansas-state", name: "Kansas State University", city: "Manhattan", state: "KS", latitude: 39.1836, longitude: -96.5717, shortName: "K-State" },
  { id: "kent-state", name: "Kent State University", city: "Kent", state: "OH", latitude: 41.1490, longitude: -81.3418 },
  { id: "kentucky", name: "University of Kentucky", city: "Lexington", state: "KY", latitude: 38.0307, longitude: -84.5040, shortName: "Kentucky" },
  
  // L
  { id: "lehigh", name: "Lehigh University", city: "Bethlehem", state: "PA", latitude: 40.6069, longitude: -75.3783 },
  { id: "liberty", name: "Liberty University", city: "Lynchburg", state: "VA", latitude: 37.3526, longitude: -79.1826 },
  { id: "louisiana-state", name: "Louisiana State University", city: "Baton Rouge", state: "LA", latitude: 30.4133, longitude: -91.1800, shortName: "LSU" },
  { id: "louisiana-tech", name: "Louisiana Tech University", city: "Ruston", state: "LA", latitude: 32.5280, longitude: -92.6479 },
  { id: "louisville", name: "University of Louisville", city: "Louisville", state: "KY", latitude: 38.2147, longitude: -85.7586, shortName: "Louisville" },
  { id: "loyola-chicago", name: "Loyola University Chicago", city: "Chicago", state: "IL", latitude: 41.9998, longitude: -87.6585 },
  { id: "loyola-marymount", name: "Loyola Marymount University", city: "Los Angeles", state: "CA", latitude: 33.9696, longitude: -118.4184, shortName: "LMU" },
  
  // M
  { id: "maine", name: "University of Maine", city: "Orono", state: "ME", latitude: 44.9010, longitude: -68.6718 },
  { id: "marquette", name: "Marquette University", city: "Milwaukee", state: "WI", latitude: 43.0385, longitude: -87.9304 },
  { id: "maryland", name: "University of Maryland, College Park", city: "College Park", state: "MD", latitude: 38.9869, longitude: -76.9426, shortName: "Maryland" },
  { id: "massachusetts", name: "University of Massachusetts Amherst", city: "Amherst", state: "MA", latitude: 42.3912, longitude: -72.5267, shortName: "UMass" },
  { id: "memphis", name: "University of Memphis", city: "Memphis", state: "TN", latitude: 35.1187, longitude: -89.9371 },
  { id: "miami", name: "University of Miami", city: "Coral Gables", state: "FL", latitude: 25.7217, longitude: -80.2795, shortName: "Miami" },
  { id: "miami-ohio", name: "Miami University", city: "Oxford", state: "OH", latitude: 39.5091, longitude: -84.7350, shortName: "Miami OH" },
  { id: "michigan", name: "University of Michigan", city: "Ann Arbor", state: "MI", latitude: 42.2780, longitude: -83.7382, shortName: "Michigan" },
  { id: "michigan-state", name: "Michigan State University", city: "East Lansing", state: "MI", latitude: 42.7018, longitude: -84.4822, shortName: "MSU" },
  { id: "middle-tennessee", name: "Middle Tennessee State University", city: "Murfreesboro", state: "TN", latitude: 35.8489, longitude: -86.3677, shortName: "MTSU" },
  { id: "minnesota", name: "University of Minnesota", city: "Minneapolis", state: "MN", latitude: 44.9740, longitude: -93.2277, shortName: "Minnesota" },
  { id: "mississippi", name: "University of Mississippi", city: "Oxford", state: "MS", latitude: 34.3647, longitude: -89.5386, shortName: "Ole Miss" },
  { id: "mississippi-state", name: "Mississippi State University", city: "Starkville", state: "MS", latitude: 33.4504, longitude: -88.7892, shortName: "Miss State" },
  { id: "missouri", name: "University of Missouri", city: "Columbia", state: "MO", latitude: 38.9404, longitude: -92.3277, shortName: "Mizzou" },
  { id: "mit", name: "Massachusetts Institute of Technology", city: "Cambridge", state: "MA", latitude: 42.3601, longitude: -71.0942, shortName: "MIT" },
  { id: "montana", name: "University of Montana", city: "Missoula", state: "MT", latitude: 46.8625, longitude: -113.9855 },
  
  // N
  { id: "navy", name: "United States Naval Academy", city: "Annapolis", state: "MD", latitude: 38.9822, longitude: -76.4844, shortName: "Navy" },
  { id: "nc-state", name: "North Carolina State University", city: "Raleigh", state: "NC", latitude: 35.7872, longitude: -78.6705, shortName: "NC State" },
  { id: "nebraska", name: "University of Nebraska-Lincoln", city: "Lincoln", state: "NE", latitude: 40.8202, longitude: -96.7005, shortName: "Nebraska" },
  { id: "nevada", name: "University of Nevada, Reno", city: "Reno", state: "NV", latitude: 39.5439, longitude: -119.8175 },
  { id: "nevada-las-vegas", name: "University of Nevada, Las Vegas", city: "Las Vegas", state: "NV", latitude: 36.1084, longitude: -115.1440, shortName: "UNLV" },
  { id: "new-hampshire", name: "University of New Hampshire", city: "Durham", state: "NH", latitude: 43.1348, longitude: -70.9358 },
  { id: "new-mexico", name: "University of New Mexico", city: "Albuquerque", state: "NM", latitude: 35.0844, longitude: -106.6189 },
  { id: "new-mexico-state", name: "New Mexico State University", city: "Las Cruces", state: "NM", latitude: 32.2818, longitude: -106.7471 },
  { id: "north-carolina", name: "University of North Carolina at Chapel Hill", city: "Chapel Hill", state: "NC", latitude: 35.9049, longitude: -79.0469, shortName: "UNC" },
  { id: "north-carolina-charlotte", name: "University of North Carolina at Charlotte", city: "Charlotte", state: "NC", latitude: 35.3063, longitude: -80.7327, shortName: "UNCC" },
  { id: "north-texas", name: "University of North Texas", city: "Denton", state: "TX", latitude: 33.2073, longitude: -97.1526, shortName: "UNT" },
  { id: "northeastern", name: "Northeastern University", city: "Boston", state: "MA", latitude: 42.3398, longitude: -71.0892 },
  { id: "northern-illinois", name: "Northern Illinois University", city: "DeKalb", state: "IL", latitude: 41.9348, longitude: -88.7717 },
  { id: "northwestern", name: "Northwestern University", city: "Evanston", state: "IL", latitude: 42.0565, longitude: -87.6753, shortName: "Northwestern" },
  { id: "notre-dame", name: "University of Notre Dame", city: "Notre Dame", state: "IN", latitude: 41.7002, longitude: -86.2379, shortName: "Notre Dame" },
  { id: "nyu", name: "New York University", city: "New York", state: "NY", latitude: 40.7295, longitude: -73.9965, shortName: "NYU" },
  
  // O
  { id: "ohio", name: "Ohio University", city: "Athens", state: "OH", latitude: 39.3245, longitude: -82.1013 },
  { id: "ohio-state", name: "The Ohio State University", city: "Columbus", state: "OH", latitude: 40.0067, longitude: -83.0305, shortName: "Ohio State" },
  { id: "oklahoma", name: "University of Oklahoma", city: "Norman", state: "OK", latitude: 35.2059, longitude: -97.4457, shortName: "Oklahoma" },
  { id: "oklahoma-state", name: "Oklahoma State University", city: "Stillwater", state: "OK", latitude: 36.1257, longitude: -97.0666, shortName: "OSU" },
  { id: "old-dominion", name: "Old Dominion University", city: "Norfolk", state: "VA", latitude: 36.8853, longitude: -76.3055, shortName: "ODU" },
  { id: "oregon", name: "University of Oregon", city: "Eugene", state: "OR", latitude: 44.0448, longitude: -123.0726, shortName: "Oregon" },
  { id: "oregon-state", name: "Oregon State University", city: "Corvallis", state: "OR", latitude: 44.5638, longitude: -123.2794, shortName: "OSU" },
  
  // P
  { id: "penn", name: "University of Pennsylvania", city: "Philadelphia", state: "PA", latitude: 39.9522, longitude: -75.1932, shortName: "Penn" },
  { id: "penn-state", name: "Pennsylvania State University", city: "University Park", state: "PA", latitude: 40.7982, longitude: -77.8599, shortName: "Penn State" },
  { id: "pepperdine", name: "Pepperdine University", city: "Malibu", state: "CA", latitude: 34.0366, longitude: -118.7085 },
  { id: "pittsburgh", name: "University of Pittsburgh", city: "Pittsburgh", state: "PA", latitude: 40.4443, longitude: -79.9608, shortName: "Pitt" },
  { id: "portland", name: "University of Portland", city: "Portland", state: "OR", latitude: 45.5714, longitude: -122.7269 },
  { id: "princeton", name: "Princeton University", city: "Princeton", state: "NJ", latitude: 40.3431, longitude: -74.6551, shortName: "Princeton" },
  { id: "providence", name: "Providence College", city: "Providence", state: "RI", latitude: 41.8420, longitude: -71.4355 },
  { id: "purdue", name: "Purdue University", city: "West Lafayette", state: "IN", latitude: 40.4237, longitude: -86.9212, shortName: "Purdue" },
  
  // R
  { id: "rhode-island", name: "University of Rhode Island", city: "Kingston", state: "RI", latitude: 41.4862, longitude: -71.5267 },
  { id: "rice", name: "Rice University", city: "Houston", state: "TX", latitude: 29.7174, longitude: -95.4018, shortName: "Rice" },
  { id: "richmond", name: "University of Richmond", city: "Richmond", state: "VA", latitude: 37.5753, longitude: -77.5394 },
  { id: "rochester", name: "University of Rochester", city: "Rochester", state: "NY", latitude: 43.1289, longitude: -77.6289 },
  { id: "rutgers", name: "Rutgers University", city: "New Brunswick", state: "NJ", latitude: 40.5008, longitude: -74.4474, shortName: "Rutgers" },
  
  // S
  { id: "sacred-heart", name: "Sacred Heart University", city: "Fairfield", state: "CT", latitude: 41.2206, longitude: -73.2412 },
  { id: "saint-josephs", name: "Saint Joseph's University", city: "Philadelphia", state: "PA", latitude: 39.9969, longitude: -75.2421 },
  { id: "saint-louis", name: "Saint Louis University", city: "St. Louis", state: "MO", latitude: 38.6368, longitude: -90.2340, shortName: "SLU" },
  { id: "sam-houston", name: "Sam Houston State University", city: "Huntsville", state: "TX", latitude: 30.7150, longitude: -95.5442 },
  { id: "san-diego", name: "University of San Diego", city: "San Diego", state: "CA", latitude: 32.7719, longitude: -117.1879 },
  { id: "san-diego-state", name: "San Diego State University", city: "San Diego", state: "CA", latitude: 32.7757, longitude: -117.0719, shortName: "SDSU" },
  { id: "san-francisco", name: "University of San Francisco", city: "San Francisco", state: "CA", latitude: 37.7767, longitude: -122.4506, shortName: "USF" },
  { id: "san-jose-state", name: "San Jose State University", city: "San Jose", state: "CA", latitude: 37.3352, longitude: -121.8811, shortName: "SJSU" },
  { id: "santa-clara", name: "Santa Clara University", city: "Santa Clara", state: "CA", latitude: 37.3496, longitude: -121.9390 },
  { id: "seton-hall", name: "Seton Hall University", city: "South Orange", state: "NJ", latitude: 40.7426, longitude: -74.2430 },
  { id: "smu", name: "Southern Methodist University", city: "Dallas", state: "TX", latitude: 32.8412, longitude: -96.7846, shortName: "SMU" },
  { id: "south-alabama", name: "University of South Alabama", city: "Mobile", state: "AL", latitude: 30.6970, longitude: -88.1782 },
  { id: "south-carolina", name: "University of South Carolina", city: "Columbia", state: "SC", latitude: 33.9940, longitude: -81.0301, shortName: "South Carolina" },
  { id: "south-florida", name: "University of South Florida", city: "Tampa", state: "FL", latitude: 28.0587, longitude: -82.4139, shortName: "USF" },
  { id: "southern-california", name: "University of Southern California", city: "Los Angeles", state: "CA", latitude: 34.0224, longitude: -118.2851, shortName: "USC" },
  { id: "southern-illinois", name: "Southern Illinois University Carbondale", city: "Carbondale", state: "IL", latitude: 37.7173, longitude: -89.2171 },
  { id: "stanford", name: "Stanford University", city: "Stanford", state: "CA", latitude: 37.4275, longitude: -122.1697, shortName: "Stanford" },
  { id: "stony-brook", name: "Stony Brook University", city: "Stony Brook", state: "NY", latitude: 40.9126, longitude: -73.1234 },
  { id: "syracuse", name: "Syracuse University", city: "Syracuse", state: "NY", latitude: 43.0392, longitude: -76.1351, shortName: "Syracuse" },
  
  // T
  { id: "tcu", name: "Texas Christian University", city: "Fort Worth", state: "TX", latitude: 32.7098, longitude: -97.3628, shortName: "TCU" },
  { id: "temple", name: "Temple University", city: "Philadelphia", state: "PA", latitude: 39.9812, longitude: -75.1554 },
  { id: "tennessee", name: "University of Tennessee", city: "Knoxville", state: "TN", latitude: 35.9544, longitude: -83.9295, shortName: "Tennessee" },
  { id: "texas", name: "University of Texas at Austin", city: "Austin", state: "TX", latitude: 30.2849, longitude: -97.7341, shortName: "Texas" },
  { id: "texas-am", name: "Texas A&M University", city: "College Station", state: "TX", latitude: 30.6187, longitude: -96.3365, shortName: "Texas A&M" },
  { id: "texas-state", name: "Texas State University", city: "San Marcos", state: "TX", latitude: 29.8884, longitude: -97.9384 },
  { id: "texas-tech", name: "Texas Tech University", city: "Lubbock", state: "TX", latitude: 33.5843, longitude: -101.8783, shortName: "Texas Tech" },
  { id: "toledo", name: "University of Toledo", city: "Toledo", state: "OH", latitude: 41.6579, longitude: -83.6147 },
  { id: "towson", name: "Towson University", city: "Towson", state: "MD", latitude: 39.3934, longitude: -76.6074 },
  { id: "troy", name: "Troy University", city: "Troy", state: "AL", latitude: 31.7996, longitude: -85.9563 },
  { id: "tufts", name: "Tufts University", city: "Medford", state: "MA", latitude: 42.4085, longitude: -71.1183 },
  { id: "tulane", name: "Tulane University", city: "New Orleans", state: "LA", latitude: 29.9400, longitude: -90.1205, shortName: "Tulane" },
  { id: "tulsa", name: "University of Tulsa", city: "Tulsa", state: "OK", latitude: 36.1506, longitude: -95.9451 },
  
  // U
  { id: "uab", name: "University of Alabama at Birmingham", city: "Birmingham", state: "AL", latitude: 33.5021, longitude: -86.8086, shortName: "UAB" },
  { id: "utah", name: "University of Utah", city: "Salt Lake City", state: "UT", latitude: 40.7649, longitude: -111.8421, shortName: "Utah" },
  { id: "utah-state", name: "Utah State University", city: "Logan", state: "UT", latitude: 41.7420, longitude: -111.8097, shortName: "Utah State" },
  { id: "uc-berkeley", name: "University of California, Berkeley", city: "Berkeley", state: "CA", latitude: 37.8719, longitude: -122.2585, shortName: "UC Berkeley" },
  { id: "uc-davis", name: "University of California, Davis", city: "Davis", state: "CA", latitude: 38.5382, longitude: -121.7617, shortName: "UC Davis" },
  { id: "uc-irvine", name: "University of California, Irvine", city: "Irvine", state: "CA", latitude: 33.6405, longitude: -117.8443, shortName: "UC Irvine" },
  { id: "uc-riverside", name: "University of California, Riverside", city: "Riverside", state: "CA", latitude: 33.9737, longitude: -117.3281, shortName: "UC Riverside" },
  { id: "uc-san-diego", name: "University of California, San Diego", city: "La Jolla", state: "CA", latitude: 32.8801, longitude: -117.2340, shortName: "UCSD" },
  { id: "uc-santa-barbara", name: "University of California, Santa Barbara", city: "Santa Barbara", state: "CA", latitude: 34.4140, longitude: -119.8489, shortName: "UCSB" },
  { id: "uc-santa-cruz", name: "University of California, Santa Cruz", city: "Santa Cruz", state: "CA", latitude: 36.9914, longitude: -122.0609, shortName: "UCSC" },
  { id: "ucla", name: "University of California, Los Angeles", city: "Los Angeles", state: "CA", latitude: 34.0689, longitude: -118.4452, shortName: "UCLA" },
  { id: "utep", name: "University of Texas at El Paso", city: "El Paso", state: "TX", latitude: 31.7697, longitude: -106.5040, shortName: "UTEP" },
  { id: "utsa", name: "University of Texas at San Antonio", city: "San Antonio", state: "TX", latitude: 29.5834, longitude: -98.6199, shortName: "UTSA" },
  
  // V
  { id: "vanderbilt", name: "Vanderbilt University", city: "Nashville", state: "TN", latitude: 36.1447, longitude: -86.8027, shortName: "Vanderbilt" },
  { id: "vermont", name: "University of Vermont", city: "Burlington", state: "VT", latitude: 44.4779, longitude: -73.1965 },
  { id: "villanova", name: "Villanova University", city: "Villanova", state: "PA", latitude: 40.0357, longitude: -75.3401, shortName: "Villanova" },
  { id: "virginia", name: "University of Virginia", city: "Charlottesville", state: "VA", latitude: 38.0336, longitude: -78.5080, shortName: "UVA" },
  { id: "virginia-commonwealth", name: "Virginia Commonwealth University", city: "Richmond", state: "VA", latitude: 37.5485, longitude: -77.4529, shortName: "VCU" },
  { id: "virginia-tech", name: "Virginia Tech", city: "Blacksburg", state: "VA", latitude: 37.2284, longitude: -80.4234, shortName: "Virginia Tech" },
  
  // W
  { id: "wake-forest", name: "Wake Forest University", city: "Winston-Salem", state: "NC", latitude: 36.1343, longitude: -80.2766, shortName: "Wake Forest" },
  { id: "washington", name: "University of Washington", city: "Seattle", state: "WA", latitude: 47.6553, longitude: -122.3035, shortName: "UW" },
  { id: "washington-state", name: "Washington State University", city: "Pullman", state: "WA", latitude: 46.7298, longitude: -117.1817, shortName: "WSU" },
  { id: "west-virginia", name: "West Virginia University", city: "Morgantown", state: "WV", latitude: 39.6350, longitude: -79.9545, shortName: "WVU" },
  { id: "western-kentucky", name: "Western Kentucky University", city: "Bowling Green", state: "KY", latitude: 36.9866, longitude: -86.4576 },
  { id: "western-michigan", name: "Western Michigan University", city: "Kalamazoo", state: "MI", latitude: 42.2830, longitude: -85.6123 },
  { id: "wichita-state", name: "Wichita State University", city: "Wichita", state: "KS", latitude: 37.7188, longitude: -97.2945 },
  { id: "william-mary", name: "William & Mary", city: "Williamsburg", state: "VA", latitude: 37.2707, longitude: -76.7075 },
  { id: "wisconsin", name: "University of Wisconsin-Madison", city: "Madison", state: "WI", latitude: 43.0731, longitude: -89.4012, shortName: "Wisconsin" },
  { id: "wright-state", name: "Wright State University", city: "Dayton", state: "OH", latitude: 39.7823, longitude: -84.0627 },
  { id: "wyoming", name: "University of Wyoming", city: "Laramie", state: "WY", latitude: 41.3149, longitude: -105.5666 },
  
  // X
  { id: "xavier", name: "Xavier University", city: "Cincinnati", state: "OH", latitude: 39.1488, longitude: -84.4736 },
  
  // Y
  { id: "yale", name: "Yale University", city: "New Haven", state: "CT", latitude: 41.3163, longitude: -72.9223, shortName: "Yale" },
  { id: "youngstown-state", name: "Youngstown State University", city: "Youngstown", state: "OH", latitude: 41.1067, longitude: -80.6469 },
];

// Helper function to search universities
// Prioritizes results that START with the query, then includes partial matches
export function searchUniversities(query: string, limit: number = 10): University[] {
  if (!query || query.length < 1) return [];
  
  const lowerQuery = query.toLowerCase();
  
  // Split into exact start matches and contains matches
  const startsWithMatches: University[] = [];
  const containsMatches: University[] = [];
  
  for (const uni of US_UNIVERSITIES) {
    const nameLower = uni.name.toLowerCase();
    const shortNameLower = uni.shortName?.toLowerCase() || '';
    const cityLower = uni.city.toLowerCase();
    
    // Check if name or shortName STARTS with the query
    if (nameLower.startsWith(lowerQuery) || shortNameLower.startsWith(lowerQuery)) {
      startsWithMatches.push(uni);
    } 
    // Otherwise check if it contains the query anywhere
    else if (
      nameLower.includes(lowerQuery) ||
      shortNameLower.includes(lowerQuery) ||
      cityLower.includes(lowerQuery)
    ) {
      containsMatches.push(uni);
    }
  }
  
  // Return starts-with matches first, then contains matches
  return [...startsWithMatches, ...containsMatches].slice(0, limit);
}

// Helper function to find university by ID
export function getUniversityById(id: string): University | undefined {
  return US_UNIVERSITIES.find(uni => uni.id === id);
}

// Helper function to get university by coordinates (find nearest)
export function getNearestUniversity(lat: number, lng: number): University | undefined {
  if (!lat || !lng) return undefined;
  
  let nearest: University | undefined;
  let minDistance = Infinity;
  
  for (const uni of US_UNIVERSITIES) {
    const distance = haversineDistance(lat, lng, uni.latitude, uni.longitude);
    if (distance < minDistance) {
      minDistance = distance;
      nearest = uni;
    }
  }
  
  return nearest;
}

// Haversine formula to calculate distance between two points
function haversineDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371; // Earth's radius in km
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = 
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function toRad(deg: number): number {
  return deg * (Math.PI / 180);
}

export default US_UNIVERSITIES;

