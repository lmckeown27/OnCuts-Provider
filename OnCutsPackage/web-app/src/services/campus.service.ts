import api from './api.service';
import type { Campus, PaginatedResponse, Barber } from '../types';

/**
 * Known acronyms/short names for universities
 * Maps slug -> display short name
 * Only these will get a shortName - all others use full name
 */
const UNIVERSITY_SHORT_NAMES: Record<string, string> = {
  // UC System
  'ucla': 'UCLA',
  'uc-berkeley': 'UC Berkeley',
  'uc-davis': 'UC Davis',
  'uc-irvine': 'UC Irvine',
  'uc-riverside': 'UC Riverside',
  'uc-san-diego': 'UCSD',
  'uc-santa-barbara': 'UCSB',
  'uc-santa-cruz': 'UCSC',
  // CSU System
  'cal-poly': 'Cal Poly SLO',
  'cal-poly-pomona': 'Cal Poly Pomona',
  'cal-state-fullerton': 'CSUF',
  'cal-state-la': 'Cal State LA',
  'cal-state-long-beach': 'CSULB',
  'cal-state-northridge': 'CSUN',
  'fresno-state': 'Fresno State',
  'san-diego-state': 'SDSU',
  'san-jose-state': 'SJSU',
  // Other well-known acronyms
  'mit': 'MIT',
  'caltech': 'Caltech',
  'nyu': 'NYU',
  'usc': 'USC',
  'southern-california': 'USC',
  'asu': 'ASU',
  'arizona-state': 'ASU',
  'osu': 'OSU',
  'ohio-state': 'Ohio State',
  'lsu': 'LSU',
  'louisiana-state': 'LSU',
  'fsu': 'FSU',
  'florida-state': 'FSU',
  'fiu': 'FIU',
  'fau': 'FAU',
  'ucf': 'UCF',
  'central-florida': 'UCF',
  'utep': 'UTEP',
  'utsa': 'UTSA',
  'unlv': 'UNLV',
  'nevada-las-vegas': 'UNLV',
  'unt': 'UNT',
  'north-texas': 'UNT',
  'uncc': 'UNCC',
  'north-carolina-charlotte': 'UNCC',
  'jmu': 'JMU',
  'james-madison': 'JMU',
  'jhu': 'JHU',
  'johns-hopkins': 'Johns Hopkins',
  'gmu': 'GMU',
  'george-mason': 'GMU',
  'vcu': 'VCU',
  'virginia-commonwealth': 'VCU',
  'wvu': 'WVU',
  'west-virginia': 'WVU',
  'byu': 'BYU',
  'brigham-young': 'BYU',
  'smu': 'SMU',
  'tcu': 'TCU',
  'ecu': 'ECU',
  'east-carolina': 'ECU',
  'odu': 'ODU',
  'old-dominion': 'ODU',
  'uab': 'UAB',
  'alabama-birmingham': 'UAB',
  'uah': 'UAH',
  'alabama-huntsville': 'UAH',
  'usf': 'USF',
  'south-florida': 'USF',
  'lmu': 'LMU',
  'loyola-marymount': 'LMU',
  'slu': 'SLU',
  'saint-louis': 'SLU',
  'bu': 'BU',
  'boston-university': 'BU',
  'bc': 'BC',
  'boston-college': 'BC',
  'gw': 'GW',
  'george-washington': 'GW',
  'cmu': 'CMU',
  'carnegie-mellon': 'CMU',
  'uconn': 'UConn',
  'connecticut': 'UConn',
  'umass': 'UMass',
  'massachusetts': 'UMass',
  'uiuc': 'UIUC',
  'illinois': 'UIUC',
  'uic': 'UIC',
  'illinois-chicago': 'UIC',
  'iu': 'IU',
  'indiana': 'IU',
  'msu': 'MSU',
  'michigan-state': 'MSU',
  'psu': 'Penn State',
  'penn-state': 'Penn State',
  'pitt': 'Pitt',
  'pittsburgh': 'Pitt',
  'uf': 'UF',
  'florida': 'UF',
  'uga': 'UGA',
  'georgia': 'UGA',
  'georgia-tech': 'Georgia Tech',
  'virginia-tech': 'Virginia Tech',
  'nc-state': 'NC State',
  'north-carolina-state': 'NC State',
  'unc': 'UNC',
  'north-carolina': 'UNC',
  'texas-am': 'Texas A&M',
  'texas-tech': 'Texas Tech',
  'iowa-state': 'Iowa State',
  'kansas-state': 'K-State',
  'colorado-state': 'CSU',
  'oregon-state': 'Oregon State',
  'washington-state': 'WSU',
  'washington': 'UW',
  'miami-ohio': 'Miami OH',
  'ole-miss': 'Ole Miss',
  'mississippi': 'Ole Miss',
  'miss-state': 'Miss State',
  'mississippi-state': 'Miss State',
  'mizzou': 'Mizzou',
  'missouri': 'Mizzou',
  'mtsu': 'MTSU',
  'middle-tennessee': 'MTSU',
};

/**
 * Derive a short name from the campus slug
 * Only returns a shortName for known acronyms - others get undefined
 */
function deriveShortName(slug: string | undefined): string | undefined {
  if (!slug) return undefined;
  return UNIVERSITY_SHORT_NAMES[slug.toLowerCase()];
}

/**
 * Transform campus data to include derived shortName
 */
function transformCampus(campus: Campus): Campus {
  return {
    ...campus,
    shortName: deriveShortName(campus.slug),
  };
}

// Non-university entries to hide from the selector (junk data)
const HIDDEN_CAMPUSES = ['gmail', 'icloud'];

class CampusService {
  async getCampuses(search?: string): Promise<Campus[]> {
    // api.get extracts response.data.data when no pagination is present
    // so the response is already the campuses array
    // No limit - fetch all universities in the system
    const campuses = await api.get<Campus[]>('/campus', { search });
    return (campuses || [])
      .filter(campus => !HIDDEN_CAMPUSES.includes(campus.name?.toLowerCase()))
      .map(transformCampus);
  }

  async getCampusById(id: string): Promise<Campus> {
    const campus = await api.get<Campus>(`/campus/${id}`);
    return transformCampus(campus);
  }

  async getCampusBarbers(campusId: string, filters?: any): Promise<PaginatedResponse<Barber>> {
    return await api.get<PaginatedResponse<Barber>>(`/campus/${campusId}/barbers`, filters);
  }
}

export default new CampusService();

