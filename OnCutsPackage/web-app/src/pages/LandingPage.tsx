/**
 * CampusCut Landing Page
 * 
 * Professional landing page with top navigation and comprehensive footer
 * Inspired by modern SaaS landing pages
 */

import React, { useState, useEffect, useCallback, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { CheckCircle, Menu, X, ExternalLink, Youtube, Instagram, Mail, ChevronDown, GraduationCap, Search, Scissors, ArrowRight, Copy, Check } from 'lucide-react';
import Button from '../components/Button';
import Card from '../components/Card';
import PullToRefresh from '../components/PullToRefresh';
import BarberApplicationModal from '../components/BarberApplicationModal';
import UniversitySelector from '../components/UniversitySelector';
import type { University } from '../components/UniversitySelector';
import { CampusCutLogo } from '@assets';
import HeaderChairLogo from '../assets/logos/Header_Chair.webp';
import MainChairLogo from '../assets/logos/Main_Chair.webp';
import MobileHeaderChairLogo from '../assets/logos/Mobile_Header_Chair.webp';
import FooterChairLogo from '../assets/logos/Footer_Chair.webp';
import { useViewport } from '../hooks/useViewport';
import { API_BASE_URL } from '../config/constants';

// Storage key for selected university
const UNIVERSITY_STORAGE_KEY = 'campuscut_selected_university';

// Type for campus with optional manager data
interface CampusWithManager {
  campusId: string;
  campusName: string;
  city: string;
  state: string;
  manager: {
    barberId: string;
    userId: string;
    firstName: string;
    lastName: string;
    bio: string | null;
    profileImageUrl: string | null;
    instagramHandle: string | null;
  } | null;
}

export default function LandingPage() {
  const navigate = useNavigate();
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [mobileMenuVisible, setMobileMenuVisible] = useState(false);
  const [scrolled, setScrolled] = useState(false);
  const [showContactPopup, setShowContactPopup] = useState(false);
  const [contactVisible, setContactVisible] = useState(false);
  const [contactForm, setContactForm] = useState({ name: '', email: '', message: '' });
  const [showBarberApplication, setShowBarberApplication] = useState(false);
  const [contactSubmitted, setContactSubmitted] = useState(false);
  const [openFaq, setOpenFaq] = useState<string | null>(null);
  const [faqCategory, setFaqCategory] = useState<'consumers' | 'barbers'>('consumers');
  const [pricingCategory, setPricingCategory] = useState<'traditional' | 'campuscut'>('traditional');
  
  // Campus Manager section state
  const [campusesWithManagers, setCampusesWithManagers] = useState<CampusWithManager[]>([]);
  const [showCampusManagerInfo, setShowCampusManagerInfo] = useState(false);
  const [campusManagerInfoVisible, setCampusManagerInfoVisible] = useState(false);
  const [emailCopied, setEmailCopied] = useState(false);
  const [selectedCampusId, setSelectedCampusId] = useState<string | null>(null);
  const [campusSearchQuery, setCampusSearchQuery] = useState('');
  const [campusDropdownOpen, setCampusDropdownOpen] = useState(false);
  const campusDropdownRef = useRef<HTMLDivElement>(null);
  
  // University selector state for hero section
  const [selectedUniversity, setSelectedUniversity] = useState<University | null>(null);
  
  // Viewport detection for responsive layout
  const { isMobile, isMobilePortrait, isMd, viewport } = useViewport();
  
  // Handle university selection - save to localStorage and navigate to consumer page
  const handleUniversitySelect = useCallback((university: University | null) => {
    setSelectedUniversity(university);
    if (university) {
      localStorage.setItem(UNIVERSITY_STORAGE_KEY, JSON.stringify(university));
    }
  }, []);
  
  // Navigate to consumer page when university is selected
  const goToConsumerPage = useCallback(() => {
    if (selectedUniversity) {
      navigate('/web/consumer');
    }
  }, [selectedUniversity, navigate]);
  
  // Mobile menu open/close with animation
  const openMobileMenu = () => {
    setMobileMenuOpen(true);
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        setMobileMenuVisible(true);
      });
    });
  };
  
  const closeMobileMenu = () => {
    setMobileMenuVisible(false);
    setTimeout(() => {
      setMobileMenuOpen(false);
    }, 200);
  };
  
  const toggleMobileMenu = () => {
    if (mobileMenuOpen) {
      closeMobileMenu();
    } else {
      openMobileMenu();
    }
  };
  
  // Close mobile menu when viewport changes to desktop (md breakpoint = 768px)
  // Use isMd check since hamburger is visible via md:hidden (< 768px)
  useEffect(() => {
    if (isMd && mobileMenuOpen) {
      closeMobileMenu();
    }
  }, [isMd, mobileMenuOpen]);

  const toggleFaq = (id: string) => {
    setOpenFaq(openFaq === id ? null : id);
  };

  const openContactPopup = () => {
    setShowContactPopup(true);
    // Trigger animation after mount
    setTimeout(() => setContactVisible(true), 10);
  };

  const closeContactPopup = () => {
    setContactVisible(false);
    setTimeout(() => {
      setShowContactPopup(false);
      setContactSubmitted(false);
      setContactForm({ name: '', email: '', message: '' });
    }, 200);
  };

  // Campus Manager info popup handlers
  const openCampusManagerInfo = () => {
    setShowCampusManagerInfo(true);
    setTimeout(() => setCampusManagerInfoVisible(true), 10);
  };

  const closeCampusManagerInfo = () => {
    setCampusManagerInfoVisible(false);
    setTimeout(() => {
      setShowCampusManagerInfo(false);
      setEmailCopied(false);
    }, 200);
  };

  const copyEmailToClipboard = async () => {
    try {
      await navigator.clipboard.writeText('campuscuthelp@gmail.com');
      setEmailCopied(true);
      setTimeout(() => setEmailCopied(false), 2000);
    } catch (err) {
      console.error('Failed to copy email:', err);
    }
  };

  // Handle scroll for sticky navigation
  useEffect(() => {
    window.scrollTo(0, 0);
  }, []);

  useEffect(() => {
    const handleScroll = () => {
      setScrolled(window.scrollY > 20);
    };
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  // Fetch campuses with campus managers for the Campus Manager section
  useEffect(() => {
    const fetchCampusesWithManagers = async () => {
      try {
        const response = await fetch(`${API_BASE_URL}/campus-manager/with-managers`);
        const data = await response.json();
        if (data.success && data.data.length > 0) {
          setCampusesWithManagers(data.data);
          // Don't auto-select - let user choose their campus
        }
      } catch (error) {
        console.error('Failed to fetch campuses with managers:', error);
      }
    };
    fetchCampusesWithManagers();
  }, []);

  // Close campus dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (campusDropdownRef.current && !campusDropdownRef.current.contains(event.target as Node)) {
        setCampusDropdownOpen(false);
      }
    };

    if (campusDropdownOpen) {
      document.addEventListener('mousedown', handleClickOutside);
    }

    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, [campusDropdownOpen]);

  const selectedCampus = campusesWithManagers.find(c => c.campusId === selectedCampusId);

  const scrollToSection = (id: string) => {
    const element = document.getElementById(id);
    if (element) {
      element.scrollIntoView({ behavior: 'smooth', block: 'start' });
      setMobileMenuOpen(false);
    }
  };

  // Pull-to-refresh handler for mobile - reload the page
  const handlePullToRefresh = async () => {
    window.location.reload();
  };

  return (
    <PullToRefresh onRefresh={handlePullToRefresh} className="min-h-screen bg-white">
      {/* Top Navigation */}
      <nav className={`fixed top-0 left-0 right-0 z-50 transition-all duration-300 ${
        scrolled ? 'bg-white shadow-md' : 'bg-transparent'
      }`}>
        <div className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between h-16 relative">
            {/* Mobile Menu Button - Left on mobile */}
            <button
              onClick={toggleMobileMenu}
              className="md:hidden p-2 rounded-lg hover:bg-gray-100 transition-colors relative w-10 h-10 flex items-center justify-center"
            >
              <Menu 
                className={`w-6 h-6 absolute transition-all duration-200 ease-out ${
                  mobileMenuVisible 
                    ? 'opacity-0 rotate-90 scale-50' 
                    : 'opacity-100 rotate-0 scale-100'
                }`} 
              />
              <X 
                className={`w-6 h-6 absolute transition-all duration-200 ease-out ${
                  mobileMenuVisible 
                    ? 'opacity-100 rotate-0 scale-100' 
                    : 'opacity-0 -rotate-90 scale-50'
                }`} 
              />
            </button>
            
            {/* Logo - centered on mobile, left on desktop */}
            <button 
              onClick={() => window.scrollTo({ top: 0, behavior: 'smooth' })}
              className="flex items-center gap-3 hover:opacity-80 transition-opacity md:relative absolute left-1/2 -translate-x-1/2 md:left-0 md:translate-x-0"
            >
              {/* Desktop logo with scroll effect */}
              <div className="relative hidden md:block">
                <img 
                  src={HeaderChairLogo} 
                  alt="CampusCut" 
                  className={`h-12 w-auto transition-opacity duration-300 ${scrolled ? 'opacity-0' : 'opacity-100'}`} 
                />
                <img 
                  src={MainChairLogo} 
                  alt="CampusCut" 
                  className={`h-12 w-auto absolute top-0 left-0 transition-opacity duration-300 ${scrolled ? 'opacity-100' : 'opacity-0'}`} 
                />
              </div>
              {/* Mobile logo with instant swap on scroll */}
              <div className="relative md:hidden">
                <img 
                  src={MobileHeaderChairLogo} 
                  alt="CampusCut" 
                  className={`h-12 w-auto ${scrolled ? 'opacity-0' : 'opacity-100'}`} 
                />
                <img 
                  src={MainChairLogo} 
                  alt="CampusCut" 
                  className={`h-12 w-auto absolute top-0 left-0 ${scrolled ? 'opacity-100' : 'opacity-0'}`} 
                />
              </div>
              <span className={`hidden md:block text-2xl font-bold transition-colors duration-300 ${scrolled ? 'text-gray-900' : 'text-gray-900'}`}>
                CampusCut
              </span>
            </button>

            {/* Desktop Navigation */}
            <div className="hidden md:flex items-center gap-8">
              <button onClick={() => scrollToSection('how-it-works')} className="text-gray-700 hover:text-primary-600 font-medium transition-colors">
                See Our Work
              </button>
              <button onClick={() => scrollToSection('campus-manager')} className="text-gray-700 hover:text-primary-600 font-medium transition-colors">
                Campus Manager
              </button>
              <button onClick={() => scrollToSection('pricing')} className="text-gray-700 hover:text-primary-600 font-medium transition-colors">
                Pricing Explained
              </button>
              <button onClick={() => scrollToSection('faq')} className="text-gray-700 hover:text-primary-600 font-medium transition-colors">
                FAQ
              </button>
            </div>

            {/* CTA Buttons - Desktop */}
            <div className="hidden md:flex items-center gap-4">
              <button
                onClick={() => navigate('/web')}
                className="px-5 py-2 bg-primary-400 hover:bg-primary-500 text-white font-medium rounded-lg transition-colors shadow-sm"
              >
                Sign In
              </button>
            </div>

            {/* Right spacer for mobile to balance the menu button */}
            <div className="w-10 md:hidden" />
          </div>
        </div>

        {/* Mobile Menu */}
        {mobileMenuOpen && (
          <div 
            className={`md:hidden bg-white border-t border-gray-200 shadow-lg overflow-hidden transition-all duration-200 ease-out ${
              mobileMenuVisible 
                ? 'max-h-96 opacity-100' 
                : 'max-h-0 opacity-0'
            }`}
          >
            <div className={`px-4 py-4 space-y-3 transition-all duration-200 ${
              mobileMenuVisible ? 'translate-y-0' : '-translate-y-2'
            }`}>
              <button onClick={() => scrollToSection('how-it-works')} className="block w-full text-left px-4 py-2 text-gray-700 hover:bg-gray-50 rounded-lg transition-colors">
                See Our Work
              </button>
              <button onClick={() => scrollToSection('campus-manager')} className="block w-full text-left px-4 py-2 text-gray-700 hover:bg-gray-50 rounded-lg transition-colors">
                Campus Manager
              </button>
              <button onClick={() => scrollToSection('pricing')} className="block w-full text-left px-4 py-2 text-gray-700 hover:bg-gray-50 rounded-lg transition-colors">
                Pricing Explained
              </button>
              <button onClick={() => scrollToSection('faq')} className="block w-full text-left px-4 py-2 text-gray-700 hover:bg-gray-50 rounded-lg transition-colors">
                FAQ
              </button>
              <div className="pt-3 border-t border-gray-200">
                <button 
                  onClick={() => {
                    closeMobileMenu();
                    navigate('/web');
                  }} 
                  className="w-full px-4 py-3 bg-primary-400 hover:bg-primary-500 text-white font-semibold rounded-lg transition-colors"
                >
                  Sign In
                </button>
              </div>
            </div>
          </div>
        )}
      </nav>

      {/* Stats Banner */}
      <div className="pt-20 bg-gradient-to-br from-primary-50 via-white to-pink-50">
        <div className="max-w-4xl mx-auto px-4 py-6 sm:py-8">
          <div className="flex flex-row items-center justify-center gap-4 sm:gap-12 md:gap-20">
            {/* Stat 1 - Total Cuts */}
            <div className="text-center">
              <div className="flex items-baseline justify-center gap-0.5 sm:gap-1">
                <span className="text-2xl sm:text-5xl font-bold text-primary-600">1,000</span>
                <span className="text-lg sm:text-3xl font-bold text-primary-500">+</span>
              </div>
              <p className="text-gray-600 text-xs sm:text-base mt-0.5 sm:mt-1">completed cuts nationwide</p>
            </div>
            
            {/* Divider */}
            <div className="w-px h-10 sm:h-16 bg-gray-300" />
            
            {/* Stat 2 - Reviews */}
            <div className="text-center">
              <div className="flex items-baseline justify-center gap-0.5 sm:gap-1">
                <span className="text-2xl sm:text-5xl font-bold text-primary-600">100</span>
                <span className="text-lg sm:text-3xl font-bold text-primary-500">+</span>
              </div>
              <div className="flex items-center justify-center gap-1 mt-0.5 sm:mt-1">
                <div className="flex">
                  {[...Array(5)].map((_, i) => (
                    <svg key={i} className="w-3 h-3 sm:w-4 sm:h-4 text-yellow-400 fill-current" viewBox="0 0 20 20">
                      <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                    </svg>
                  ))}
                </div>
                <span className="text-gray-600 text-xs sm:text-base">reviews per campus</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Hero Section */}
      <div className="py-20 px-4 bg-gradient-to-br from-primary-50 via-white to-pink-50 flex flex-col items-center justify-center min-h-[50vh]">
          {/* Mobile Logo */}
          <h1 className="sm:hidden text-3xl font-bold text-primary-600 mb-6">CampusCut</h1>
          
          {/* University Selector */}
        <div className="w-full max-w-xl mb-8">
          <div className="bg-white rounded-2xl shadow-lg p-3 sm:p-4">
              <UniversitySelector
                value={selectedUniversity}
                onChange={handleUniversitySelect}
                placeholder="Search for your university..."
              />
            </div>
            {selectedUniversity && (
            <p className="mt-4 text-sm text-gray-600 text-center">
                Searching barbers at {selectedUniversity.shortName || selectedUniversity.name}
              </p>
            )}
          </div>
          
          {/* CTA Button */}
            <button
              onClick={goToConsumerPage}
              disabled={!selectedUniversity}
              className={`px-16 py-7 sm:py-8 font-bold text-2xl sm:text-3xl md:text-4xl rounded-3xl transition-all shadow-xl hover:shadow-2xl active:scale-95 ${
                selectedUniversity 
                  ? 'bg-primary-400 hover:bg-primary-500 text-white cursor-pointer' 
                  : 'bg-gray-300 text-gray-500 cursor-not-allowed'
              }`}
            >
              Find Barber
            </button>
      </div>

      {/* Portfolio Section - Video Showcase */}
      <div className="py-20 px-4 bg-white shadow-[0_-4px_20px_-4px_rgba(0,0,0,0.1)]" id="how-it-works">
        <div className="max-w-6xl mx-auto bg-white">
          <div className="text-center mb-12">
            <h2 className="text-4xl md:text-5xl font-bold text-gray-900 mb-4">
              See Our Work
            </h2>
            <p className="text-lg text-gray-600 max-w-2xl mx-auto">
              Check out some of the amazing cuts from our talented campus barbers
            </p>
          </div>
          
          {/* Video Grid - 3 YouTube Shorts (autoplay, muted, looping) */}
          {/* Mobile: 1 video centered, Desktop: 3 videos in grid */}
          <div className="flex justify-center md:grid md:grid-cols-3 gap-6 md:gap-8 bg-white">
            {/* Video 1 - Always visible */}
            <div className="relative w-full max-w-xs md:max-w-none rounded-2xl shadow-lg shadow-gray-300 overflow-hidden bg-black" style={{ aspectRatio: '9/16' }}>
              <iframe
                className="absolute top-0 left-0 w-full h-full pointer-events-none"
                src="https://www.youtube.com/embed/I9MlYYn4wUM?autoplay=1&mute=1&loop=1&playlist=I9MlYYn4wUM&controls=0&showinfo=0&rel=0&modestbranding=1&disablekb=1&fs=0&iv_load_policy=3&playsinline=1"
                title="CampusCut Showcase 1"
                frameBorder="0"
                allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                loading="lazy"
              ></iframe>
              {/* Transparent overlay to block all interaction */}
              <div className="absolute inset-0 z-10" />
            </div>
            
            {/* Video 2 - Hidden on mobile */}
            <div className="hidden md:block relative w-full rounded-2xl shadow-lg shadow-gray-300 overflow-hidden bg-black" style={{ aspectRatio: '9/16' }}>
              <iframe
                className="absolute top-0 left-0 w-full h-full pointer-events-none"
                src="https://www.youtube.com/embed/aPAqtReSjX0?autoplay=1&mute=1&loop=1&playlist=aPAqtReSjX0&controls=0&showinfo=0&rel=0&modestbranding=1&disablekb=1&fs=0&iv_load_policy=3&playsinline=1"
                title="CampusCut Showcase 2"
                frameBorder="0"
                allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                loading="lazy"
              ></iframe>
              {/* Transparent overlay to block all interaction */}
              <div className="absolute inset-0 z-10" />
            </div>
            
            {/* Video 3 - Hidden on mobile */}
            <div className="hidden md:block relative w-full rounded-2xl shadow-lg shadow-gray-300 overflow-hidden bg-black" style={{ aspectRatio: '9/16' }}>
              <iframe
                className="absolute top-0 left-0 w-full h-full pointer-events-none"
                src="https://www.youtube.com/embed/yi4qTTBbhx8?autoplay=1&mute=1&loop=1&playlist=yi4qTTBbhx8&controls=0&showinfo=0&rel=0&modestbranding=1&disablekb=1&fs=0&iv_load_policy=3&playsinline=1"
                title="CampusCut Showcase 3"
                frameBorder="0"
                allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                loading="lazy"
              ></iframe>
              {/* Transparent overlay to block all interaction */}
              <div className="absolute inset-0 z-10" />
            </div>
          </div>

        </div>
      </div>

      {/* Campus Manager Section */}
      <div className="py-20 px-4 bg-white shadow-[0_-4px_20px_-4px_rgba(0,0,0,0.1)]" id="campus-manager">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-12">
            <h2 className="text-4xl md:text-5xl font-bold text-gray-900 mb-4">
              Meet Your Campus Manager
            </h2>
            <p className="text-lg text-gray-600 max-w-3xl mx-auto">
              Not a bot, not A.I., but a real human being trusted to manage barbers at your campus.
            </p>
          </div>

          {campusesWithManagers.length > 0 ? (
            <div className="grid md:grid-cols-5 gap-8 items-stretch">
              {/* Left side - Campus selector and profile picture (3/5 width) */}
              <div className="md:col-span-3 flex flex-col gap-6">
                {/* Campus Selector */}
                <div className="max-w-md mx-auto w-full">
                  <label className="block text-sm font-medium text-gray-700 mb-2">Select Your Campus</label>
                  <div className="relative" ref={campusDropdownRef}>
                    <div 
                      className={`relative flex items-center bg-white border-2 rounded-xl transition-all ${
                        campusDropdownOpen ? 'border-primary-500 shadow-lg' : 'border-gray-300'
                      }`}
                    >
                      <input
                        type="text"
                        placeholder="Search for your university..."
                        value={campusSearchQuery}
                        onChange={(e) => {
                          setCampusSearchQuery(e.target.value);
                          setCampusDropdownOpen(true);
                        }}
                        onFocus={(e) => {
                          setCampusDropdownOpen(true);
                          // Auto-select text when focused so user can easily retype
                          e.target.select();
                        }}
                        className="flex-1 pl-4 pr-3 py-4 text-gray-900 placeholder-gray-400 bg-transparent outline-none text-lg"
                      />
                      <button
                        type="button"
                        onClick={() => setCampusDropdownOpen(!campusDropdownOpen)}
                        className="pr-4 text-gray-400"
                      >
                        <ChevronDown className={`w-5 h-5 transition-transform ${campusDropdownOpen ? 'rotate-180' : ''}`} />
                      </button>
                    </div>
                    
                    {campusDropdownOpen && (
                      <div className="absolute z-50 w-full mt-2 bg-white border border-gray-200 rounded-xl shadow-xl max-h-80 overflow-y-auto">
                        {campusesWithManagers
                          .filter(campus => 
                            campus.campusName.toLowerCase().includes(campusSearchQuery.toLowerCase()) ||
                            campus.city.toLowerCase().includes(campusSearchQuery.toLowerCase()) ||
                            campus.state.toLowerCase().includes(campusSearchQuery.toLowerCase())
                          )
                          .map((campus) => (
                            <button
                              key={campus.campusId}
                              type="button"
                              onClick={() => {
                                setSelectedCampusId(campus.campusId);
                                setCampusSearchQuery(`${campus.campusName} — ${campus.city}, ${campus.state}`);
                                setCampusDropdownOpen(false);
                              }}
                              className={`w-full px-4 py-3 text-left hover:bg-primary-50 transition-colors flex items-center justify-between ${
                                selectedCampusId === campus.campusId ? 'bg-primary-50 text-primary-700' : 'text-gray-700'
                              }`}
                            >
                              <span>{campus.campusName} — {campus.city}, {campus.state}</span>
                            </button>
                          ))}
                        {campusesWithManagers.filter(campus => 
                          campus.campusName.toLowerCase().includes(campusSearchQuery.toLowerCase()) ||
                          campus.city.toLowerCase().includes(campusSearchQuery.toLowerCase()) ||
                          campus.state.toLowerCase().includes(campusSearchQuery.toLowerCase())
                        ).length === 0 && (
                          <div className="p-4 text-center text-gray-500">
                            <Search className="w-8 h-8 mx-auto mb-2 text-gray-300" />
                            <p>No campuses found</p>
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                </div>

                {/* Desktop: Show campus manager profile picture below dropdown when selected */}
                {selectedCampus?.manager && (
                  <div className="hidden md:flex flex-1 justify-center items-center">
                    <div className="w-full max-w-xs aspect-square rounded-2xl overflow-hidden bg-gray-200 ring-4 ring-primary-500/30 shadow-xl">
                      {selectedCampus.manager.profileImageUrl ? (
                        <img
                          src={selectedCampus.manager.profileImageUrl}
                          alt={`${selectedCampus.manager.firstName} ${selectedCampus.manager.lastName}`}
                          className="w-full h-full object-cover"
                        />
                      ) : (
                        <div className="w-full h-full flex items-center justify-center text-5xl font-bold text-gray-400 bg-gray-100">
                          {selectedCampus.manager.firstName.charAt(0)}{selectedCampus.manager.lastName.charAt(0)}
                        </div>
                      )}
                    </div>
                  </div>
                )}

                {/* Desktop: Show "Become a Campus Manager" button below dropdown when no campus selected */}
                {!selectedCampus && (
                  <div className="hidden md:flex justify-center">
                    <button
                      onClick={openCampusManagerInfo}
                      className="inline-flex items-center gap-4 bg-primary-500 hover:bg-primary-600 text-white px-8 py-4 rounded-2xl text-lg font-bold transition-colors shadow-xl hover:shadow-2xl"
                    >
                      <Mail className="w-6 h-6" />
                      <span>Become a Campus Manager</span>
                    </button>
                  </div>
                )}

                {/* Desktop: Show apply button below dropdown when campus has no manager */}
                {selectedCampus && !selectedCampus.manager && (
                  <div className="hidden md:flex justify-center">
                    <button
                      onClick={openCampusManagerInfo}
                      className="inline-flex items-center gap-4 bg-primary-500 hover:bg-primary-600 text-white px-8 py-4 rounded-2xl text-lg font-bold transition-colors shadow-xl hover:shadow-2xl"
                    >
                      <Mail className="w-6 h-6" />
                      <span>Apply for This Position</span>
                    </button>
                  </div>
                )}

                {/* Mobile: Show placeholder card when no campus selected */}
                {!selectedCampus && (
                  <div className="md:hidden bg-gradient-to-br from-gray-900 to-gray-800 rounded-3xl p-8 text-white flex flex-col justify-center">
                    <div className="text-center">
                      <div className="w-32 h-32 mx-auto mb-6 rounded-2xl overflow-hidden bg-gray-700/50 ring-4 ring-gray-600/30 flex items-center justify-center">
                        <span className="text-4xl text-gray-500">?</span>
                      </div>
                      <h3 className="text-2xl font-bold mb-3">Select Your Campus</h3>
                      <p className="text-gray-400 text-sm max-w-xs mx-auto mb-4">
                        Choose your campus from the dropdown to meet your dedicated human Campus Manager.
                      </p>
                      <button
                        onClick={openCampusManagerInfo}
                        className="inline-flex items-center gap-2 bg-primary-500 hover:bg-primary-600 text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors"
                      >
                        <Mail className="w-4 h-4" />
                        <span>Become a Campus Manager</span>
                      </button>
                    </div>
                  </div>
                )}

                {/* Mobile: Show profile card when campus is selected */}
                {selectedCampus && (
                  <div className="md:hidden bg-gradient-to-br from-gray-900 to-gray-800 rounded-3xl p-8 text-white flex flex-col justify-center">
                    <div className="text-center">
                      {selectedCampus.manager ? (
                        <>
                          {/* Profile Image - Square */}
                          <div className="w-48 h-48 mx-auto mb-6 rounded-2xl overflow-hidden bg-gray-700 ring-4 ring-primary-500/30">
                            {selectedCampus.manager.profileImageUrl ? (
                              <img
                                src={selectedCampus.manager.profileImageUrl}
                                alt={`${selectedCampus.manager.firstName} ${selectedCampus.manager.lastName}`}
                                className="w-full h-full object-cover"
                              />
                            ) : (
                              <div className="w-full h-full flex items-center justify-center text-5xl font-bold text-gray-400">
                                {selectedCampus.manager.firstName.charAt(0)}{selectedCampus.manager.lastName.charAt(0)}
                              </div>
                            )}
                          </div>

                          {/* Name and Role */}
                          <h3 className="text-2xl font-bold mb-1">
                            {selectedCampus.manager.firstName} {selectedCampus.manager.lastName}
                          </h3>
                          <p className="text-primary-400 font-medium mb-2">Campus Manager</p>
                          <p className="text-gray-400 text-sm mb-4">{selectedCampus.campusName}</p>

                          {/* Instagram Handle */}
                          {selectedCampus.manager.instagramHandle && (
                            <a
                              href={`https://instagram.com/${selectedCampus.manager.instagramHandle.replace('@', '')}`}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="inline-flex items-center gap-2 text-gray-300 hover:text-primary-400 transition-colors mb-6"
                            >
                              <Instagram className="w-5 h-5" />
                              <span>@{selectedCampus.manager.instagramHandle.replace('@', '')}</span>
                            </a>
                          )}

                          {/* Bio */}
                          {selectedCampus.manager.bio && (
                            <div className="bg-white/10 rounded-xl p-4 text-left mt-4">
                              <p className="text-gray-300 text-sm leading-relaxed">
                                {selectedCampus.manager.bio}
                              </p>
                            </div>
                          )}
                        </>
                      ) : (
                        /* No manager for this campus yet */
                        <>
                          <div className="w-32 h-32 mx-auto mb-6 rounded-full overflow-hidden bg-gray-700 ring-4 ring-gray-600/30 flex items-center justify-center">
                            <span className="text-4xl text-gray-500">?</span>
                          </div>
                          <h3 className="text-2xl font-bold mb-1">Coming Soon</h3>
                          <p className="text-gray-400 font-medium mb-2">Campus Manager</p>
                          <p className="text-gray-500 text-sm mb-4">{selectedCampus.campusName}</p>
                          <div className="bg-white/10 rounded-xl p-4 mb-4">
                            <p className="text-gray-400 text-sm">
                              We're currently searching for a Campus Manager for this location.
                            </p>
                          </div>
                          <button
                            onClick={openCampusManagerInfo}
                            className="inline-flex items-center gap-2 bg-primary-500 hover:bg-primary-600 text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors"
                          >
                            <Mail className="w-4 h-4" />
                            <span>Apply for This Position</span>
                          </button>
                        </>
                      )}
                    </div>
                  </div>
                )}
              </div>

              {/* Right side - Campus Manager Profile (Desktop only, 2/5 width) */}
              <div className="hidden md:col-span-2 md:flex bg-gradient-to-br from-gray-900 to-gray-800 rounded-3xl p-6 text-white flex-col justify-center">
                <div className="text-center">
                  {!selectedCampus ? (
                    /* No campus selected yet - prompt user */
                    <>
                      <div className="w-32 h-32 mx-auto mb-6 rounded-2xl overflow-hidden bg-gray-700/50 ring-4 ring-gray-600/30 flex items-center justify-center">
                        <span className="text-4xl text-gray-500">?</span>
                      </div>
                      <h3 className="text-2xl font-bold mb-3">Select Your Campus</h3>
                      <p className="text-gray-400 text-sm max-w-xs mx-auto">
                        Choose your campus from the dropdown to meet your dedicated human Campus Manager.
                      </p>
                    </>
                  ) : selectedCampus.manager ? (
                      <>
                        {/* Name and Role */}
                        <h3 className="text-2xl font-bold mb-1">
                          {selectedCampus.manager.firstName} {selectedCampus.manager.lastName}
                        </h3>
                        <p className="text-primary-400 font-medium mb-2">Campus Manager</p>
                        <p className="text-gray-400 text-sm mb-4">{selectedCampus.campusName}</p>

                        {/* Instagram Handle */}
                        {selectedCampus.manager.instagramHandle && (
                          <a
                            href={`https://instagram.com/${selectedCampus.manager.instagramHandle.replace('@', '')}`}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="inline-flex items-center gap-2 text-gray-300 hover:text-primary-400 transition-colors mb-6"
                          >
                            <Instagram className="w-5 h-5" />
                            <span>@{selectedCampus.manager.instagramHandle.replace('@', '')}</span>
                          </a>
                        )}

                        {/* Bio */}
                        {selectedCampus.manager.bio && (
                          <div className="bg-white/10 rounded-xl p-4 text-left mt-4">
                            <p className="text-gray-300 text-sm leading-relaxed">
                              {selectedCampus.manager.bio}
                            </p>
                          </div>
                        )}
                      </>
                    ) : (
                      /* No manager for this campus yet */
                    <>
                      <div className="w-32 h-32 mx-auto mb-6 rounded-full overflow-hidden bg-gray-700 ring-4 ring-gray-600/30 flex items-center justify-center">
                        <span className="text-4xl text-gray-500">?</span>
                      </div>
                      <h3 className="text-2xl font-bold mb-1">Coming Soon</h3>
                      <p className="text-gray-400 font-medium mb-2">Campus Manager</p>
                      <p className="text-gray-500 text-sm mb-4">{selectedCampus.campusName}</p>
                      <div className="bg-white/10 rounded-xl p-4">
                        <p className="text-gray-400 text-sm">
                          We're currently searching for a Campus Manager for this location.
                        </p>
                      </div>
                    </>
                  )}
                </div>
              </div>
            </div>
          ) : (
            /* Fallback when no campuses with managers */
            <div className="text-center py-12">
              <div className="bg-gray-50 rounded-2xl p-8 max-w-2xl mx-auto">
                <h3 className="text-xl font-bold text-gray-900 mb-4">Campus Managers Coming Soon</h3>
                <p className="text-gray-600">
                  We're actively expanding to more campuses. Each campus will have a dedicated human Campus Manager 
                  to personally vet barbers, handle disputes, and maintain quality standards.
                </p>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Economic Comparison Section */}
      <div className="py-20 px-4 bg-gradient-to-br from-gray-50 to-primary-50 shadow-[0_-4px_20px_-4px_rgba(0,0,0,0.1)]" id="pricing">
        <div className="max-w-7xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-4xl md:text-5xl font-bold text-gray-900 mb-4">
              The Math Behind CampusCut
            </h2>
          </div>

          {/* Mobile Toggle Slider */}
          <div className="md:hidden flex justify-center mb-8">
            <div className="inline-flex bg-white rounded-full p-1 shadow-sm">
              <button
                onClick={() => setPricingCategory('traditional')}
                className={`px-5 py-2 rounded-full text-sm font-medium transition-all ${
                  pricingCategory === 'traditional'
                    ? 'bg-red-100 text-red-700'
                    : 'text-gray-600 hover:text-gray-900'
                }`}
              >
                Traditional
              </button>
              <button
                onClick={() => setPricingCategory('campuscut')}
                className={`px-5 py-2 rounded-full text-sm font-medium transition-all ${
                  pricingCategory === 'campuscut'
                    ? 'bg-green-100 text-green-700'
                    : 'text-gray-600 hover:text-gray-900'
                }`}
              >
                CampusCut
              </button>
            </div>
          </div>

          {/* The Numbers */}
          <div className="max-w-6xl mx-auto mb-12">
            <div className="grid md:grid-cols-2 gap-8">
              {/* Traditional Barbershop - Hidden on mobile when CampusCut selected */}
              <Card className={`border-2 border-red-200 bg-red-50 ${pricingCategory === 'campuscut' ? 'hidden md:block' : ''}`}>
                <div className="p-6">
                  <div className="text-center mb-6">
                    <h3 className="text-2xl font-bold text-gray-900 mb-2">Traditional Barbershop</h3>
                    <p className="text-gray-600">How it usually works</p>
                  </div>
                  
                  <div className="space-y-4">
                    <div className="bg-white rounded-lg p-4">
                      <div className="flex justify-between items-center mb-2">
                        <span className="text-gray-700 font-medium">Customer Pays:</span>
                        <span className="text-2xl font-bold text-gray-900">$35</span>
                      </div>
                      <div className="h-2 bg-gray-200 rounded-full overflow-hidden">
                        <div className="h-full bg-red-500" style={{ width: '100%' }}></div>
                      </div>
                    </div>

                    <div className="bg-white rounded-lg p-4">
                      <div className="flex justify-between items-center mb-2">
                        <span className="text-gray-700 font-medium">Shop Takes (50%):</span>
                        <span className="text-xl font-bold text-red-600">-$17.50</span>
                      </div>
                      <p className="text-xs text-gray-500">Rent, utilities, reception, overhead</p>
                    </div>

                    <div className="bg-white rounded-lg p-4 border-2 border-red-300">
                      <div className="flex justify-between items-center">
                        <span className="text-gray-900 font-bold">Barber Earns:</span>
                        <span className="text-3xl font-bold text-red-700">$17.50</span>
                      </div>
                      <p className="text-sm text-gray-600 mt-1">Only 50% of what customer paid</p>
                    </div>
                  </div>

                </div>
              </Card>

              {/* CampusCut Model - Hidden on mobile when Traditional selected */}
              <Card className={`border-2 border-green-300 bg-green-50 ${pricingCategory === 'traditional' ? 'hidden md:block' : ''}`}>
                <div className="p-6">
                  <div className="text-center mb-6">
                    <h3 className="text-2xl font-bold text-gray-900 mb-2">CampusCut</h3>
                    <p className="text-gray-600">How we're different</p>
                  </div>
                  
                  <div className="space-y-4">
                    <div className="bg-white rounded-lg p-4">
                      <div className="flex justify-between items-center mb-2">
                        <span className="text-gray-700 font-medium">Customer Pays:</span>
                        <span className="text-2xl font-bold text-gray-900">$28</span>
                      </div>
                      <div className="h-2 bg-gray-200 rounded-full overflow-hidden">
                        <div className="h-full bg-green-500" style={{ width: '100%' }}></div>
                      </div>
                    </div>

                    <div className="bg-white rounded-lg p-4">
                      <div className="flex justify-between items-center mb-2">
                        <span className="text-gray-700 font-medium">Platform Fee (15%):</span>
                        <span className="text-xl font-bold text-orange-600">-$4.20</span>
                      </div>
                      <p className="text-xs text-gray-500">No overhead, just technology</p>
                    </div>

                    <div className="bg-white rounded-lg p-4 border-2 border-green-400">
                      <div className="flex justify-between items-center">
                        <span className="text-gray-900 font-bold">Barber Earns:</span>
                        <span className="text-3xl font-bold text-green-700">$23.80</span>
                      </div>
                      <p className="text-sm text-gray-600 mt-1">85% of what customer paid</p>
                    </div>
                  </div>

                </div>
              </Card>
            </div>
          </div>

        </div>
      </div>

      {/* FAQ Section */}
      <div className="py-20 px-4 bg-white shadow-[0_-4px_20px_-4px_rgba(0,0,0,0.1)]" id="faq">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-12">
            <h2 className="text-4xl md:text-5xl font-bold text-gray-900 mb-4">
              Frequently Asked Questions
            </h2>
          </div>

          {/* Mobile Toggle Slider */}
          <div className="md:hidden flex justify-center mb-8">
            <div className="inline-flex bg-gray-100 rounded-full p-1">
              <button
                onClick={() => {
                  setFaqCategory('consumers');
                  setOpenFaq(null);
                }}
                className={`px-6 py-2 rounded-full text-sm font-medium transition-all ${
                  faqCategory === 'consumers'
                    ? 'bg-white text-gray-900 shadow-sm'
                    : 'text-gray-600 hover:text-gray-900'
                }`}
              >
                For Consumers
              </button>
              <button
                onClick={() => {
                  setFaqCategory('barbers');
                  setOpenFaq(null);
                }}
                className={`px-6 py-2 rounded-full text-sm font-medium transition-all ${
                  faqCategory === 'barbers'
                    ? 'bg-white text-gray-900 shadow-sm'
                    : 'text-gray-600 hover:text-gray-900'
                }`}
              >
                For Barbers
              </button>
            </div>
          </div>

          <div className="grid md:grid-cols-2 gap-8">
            {/* For Consumers Column - Hidden on mobile when barbers selected */}
            <div className={`${faqCategory === 'barbers' ? 'hidden md:block' : ''}`}>
              <h3 className="text-xl font-bold text-gray-900 mb-4 text-center hidden md:block">
                For Consumers
              </h3>
              <div className="space-y-3">
                <div className="bg-gradient-to-r from-gray-50 to-white border border-gray-200 rounded-xl overflow-hidden">
                  <button 
                    onClick={() => toggleFaq('c1')}
                    className="w-full flex items-center justify-center p-4 cursor-pointer hover:bg-gray-50 transition-colors gap-2"
                  >
                    <h4 className="font-medium text-gray-900">How do I book a haircut?</h4>
                    <ChevronDown className={`w-4 h-4 text-gray-500 transition-transform duration-300 flex-shrink-0 ${openFaq === 'c1' ? 'rotate-180' : ''}`} />
                  </button>
                  <div className={`grid transition-all duration-300 ease-in-out ${openFaq === 'c1' ? 'grid-rows-[1fr]' : 'grid-rows-[0fr]'}`}>
                    <div className="overflow-hidden">
                      <p className="px-4 pb-4 text-gray-600 text-sm text-center">Tap "Find Barber," browse barbers at your campus, view their Instagram portfolio, then select a service, pick an available date and time, enter your preferred location, and submit your request. You'll get a notification when the barber accepts!</p>
                    </div>
                  </div>
                </div>

                <div className="bg-gradient-to-r from-gray-50 to-white border border-gray-200 rounded-xl overflow-hidden">
                  <button 
                    onClick={() => toggleFaq('c2')}
                    className="w-full flex items-center justify-center p-4 cursor-pointer hover:bg-gray-50 transition-colors gap-2"
                  >
                    <h4 className="font-medium text-gray-900">When and how do I pay?</h4>
                    <ChevronDown className={`w-4 h-4 text-gray-500 transition-transform duration-300 flex-shrink-0 ${openFaq === 'c2' ? 'rotate-180' : ''}`} />
                  </button>
                  <div className={`grid transition-all duration-300 ease-in-out ${openFaq === 'c2' ? 'grid-rows-[1fr]' : 'grid-rows-[0fr]'}`}>
                    <div className="overflow-hidden">
                      <p className="px-4 pb-4 text-gray-600 text-sm text-center">You pay after your haircut is complete. Once the barber marks the service as done, you'll see a payment prompt. Pay securely with card, Apple Pay, or Google Pay and add a tip if you'd like (15%, 20%, or 25%).</p>
                    </div>
                  </div>
                </div>

                <div className="bg-gradient-to-r from-gray-50 to-white border border-gray-200 rounded-xl overflow-hidden">
                  <button 
                    onClick={() => toggleFaq('c3')}
                    className="w-full flex items-center justify-center p-4 cursor-pointer hover:bg-gray-50 transition-colors gap-2"
                  >
                    <h4 className="font-medium text-gray-900">Where do haircuts happen?</h4>
                    <ChevronDown className={`w-4 h-4 text-gray-500 transition-transform duration-300 flex-shrink-0 ${openFaq === 'c3' ? 'rotate-180' : ''}`} />
                  </button>
                  <div className={`grid transition-all duration-300 ease-in-out ${openFaq === 'c3' ? 'grid-rows-[1fr]' : 'grid-rows-[0fr]'}`}>
                    <div className="overflow-hidden">
                      <p className="px-4 pb-4 text-gray-600 text-sm text-center">You choose from the barber's available service locations when booking. These could be on-campus spots, dorms, or other areas. Select your preferred location from the options provided.</p>
                    </div>
                  </div>
                </div>

                <div className="bg-gradient-to-r from-gray-50 to-white border border-gray-200 rounded-xl overflow-hidden">
                  <button 
                    onClick={() => toggleFaq('c4')}
                    className="w-full flex items-center justify-center p-4 cursor-pointer hover:bg-gray-50 transition-colors gap-2"
                  >
                    <h4 className="font-medium text-gray-900">Can I edit or cancel my booking?</h4>
                    <ChevronDown className={`w-4 h-4 text-gray-500 transition-transform duration-300 flex-shrink-0 ${openFaq === 'c4' ? 'rotate-180' : ''}`} />
                  </button>
                  <div className={`grid transition-all duration-300 ease-in-out ${openFaq === 'c4' ? 'grid-rows-[1fr]' : 'grid-rows-[0fr]'}`}>
                    <div className="overflow-hidden">
                      <p className="px-4 pb-4 text-gray-600 text-sm text-center">Yes! You can edit the time, date, or location, or cancel entirely. Just do it before the barber marks the service as complete. Find these options in your booking details.</p>
                    </div>
                  </div>
                </div>

                <div className="bg-gradient-to-r from-gray-50 to-white border border-gray-200 rounded-xl overflow-hidden">
                  <button 
                    onClick={() => toggleFaq('c5')}
                    className="w-full flex items-center justify-center p-4 cursor-pointer hover:bg-gray-50 transition-colors gap-2"
                  >
                    <h4 className="font-medium text-gray-900">How do I contact my barber?</h4>
                    <ChevronDown className={`w-4 h-4 text-gray-500 transition-transform duration-300 flex-shrink-0 ${openFaq === 'c5' ? 'rotate-180' : ''}`} />
                  </button>
                  <div className={`grid transition-all duration-300 ease-in-out ${openFaq === 'c5' ? 'grid-rows-[1fr]' : 'grid-rows-[0fr]'}`}>
                    <div className="overflow-hidden">
                      <p className="px-4 pb-4 text-gray-600 text-sm text-center">Use the in-app messaging feature to chat directly with your barber. Coordinate details, share reference photos, or ask questions all in one place.</p>
                    </div>
                  </div>
                </div>

                <div className="bg-gradient-to-r from-gray-50 to-white border border-gray-200 rounded-xl overflow-hidden">
                  <button 
                    onClick={() => toggleFaq('c6')}
                    className="w-full flex items-center justify-center p-4 cursor-pointer hover:bg-gray-50 transition-colors gap-2"
                  >
                    <h4 className="font-medium text-gray-900">Is my payment secure?</h4>
                    <ChevronDown className={`w-4 h-4 text-gray-500 transition-transform duration-300 flex-shrink-0 ${openFaq === 'c6' ? 'rotate-180' : ''}`} />
                  </button>
                  <div className={`grid transition-all duration-300 ease-in-out ${openFaq === 'c6' ? 'grid-rows-[1fr]' : 'grid-rows-[0fr]'}`}>
                    <div className="overflow-hidden">
                      <p className="px-4 pb-4 text-gray-600 text-sm text-center">Absolutely. All payments are processed securely through Stripe, a trusted payment platform used by millions of businesses. We never store your card details—Stripe handles everything with bank-level encryption.</p>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            {/* For Barbers Column - Hidden on mobile when consumers selected */}
            <div className={`${faqCategory === 'consumers' ? 'hidden md:block' : ''}`}>
              <h3 className="text-xl font-bold text-gray-900 mb-4 text-center hidden md:block">
                For Barbers
              </h3>
              <div className="space-y-3">
                <div className="bg-gradient-to-r from-gray-50 to-white border border-gray-200 rounded-xl overflow-hidden">
                  <button 
                    onClick={() => toggleFaq('b1')}
                    className="w-full flex items-center justify-center p-4 cursor-pointer hover:bg-gray-50 transition-colors gap-2"
                  >
                    <h4 className="font-medium text-gray-900">How do I become a CampusCut barber?</h4>
                    <ChevronDown className={`w-4 h-4 text-gray-500 transition-transform duration-300 flex-shrink-0 ${openFaq === 'b1' ? 'rotate-180' : ''}`} />
                  </button>
                  <div className={`grid transition-all duration-300 ease-in-out ${openFaq === 'b1' ? 'grid-rows-[1fr]' : 'grid-rows-[0fr]'}`}>
                    <div className="overflow-hidden">
                      <p className="px-4 pb-4 text-gray-600 text-sm text-center">Tap "Become a Barber" and submit your application. Once approved, set up your profile with services, prices, availability, and link your Instagram portfolio. Connect Stripe to receive payments, and you're ready to start accepting bookings!</p>
                    </div>
                  </div>
                </div>

                <div className="bg-gradient-to-r from-gray-50 to-white border border-gray-200 rounded-xl overflow-hidden">
                  <button 
                    onClick={() => toggleFaq('b2')}
                    className="w-full flex items-center justify-center p-4 cursor-pointer hover:bg-gray-50 transition-colors gap-2"
                  >
                    <h4 className="font-medium text-gray-900">How much do I keep?</h4>
                    <ChevronDown className={`w-4 h-4 text-gray-500 transition-transform duration-300 flex-shrink-0 ${openFaq === 'b2' ? 'rotate-180' : ''}`} />
                  </button>
                  <div className={`grid transition-all duration-300 ease-in-out ${openFaq === 'b2' ? 'grid-rows-[1fr]' : 'grid-rows-[0fr]'}`}>
                    <div className="overflow-hidden">
                      <p className="px-4 pb-4 text-gray-600 text-sm text-center">You keep 85% of every payment, plus 100% of tips. We only take a 15% platform fee, way less than the 40-60% traditional barbershops take.</p>
                    </div>
                  </div>
                </div>

                <div className="bg-gradient-to-r from-gray-50 to-white border border-gray-200 rounded-xl overflow-hidden">
                  <button 
                    onClick={() => toggleFaq('b3')}
                    className="w-full flex items-center justify-center p-4 cursor-pointer hover:bg-gray-50 transition-colors gap-2"
                  >
                    <h4 className="font-medium text-gray-900">How does payment work?</h4>
                    <ChevronDown className={`w-4 h-4 text-gray-500 transition-transform duration-300 flex-shrink-0 ${openFaq === 'b3' ? 'rotate-180' : ''}`} />
                  </button>
                  <div className={`grid transition-all duration-300 ease-in-out ${openFaq === 'b3' ? 'grid-rows-[1fr]' : 'grid-rows-[0fr]'}`}>
                    <div className="overflow-hidden">
                      <p className="px-4 pb-4 text-gray-600 text-sm text-center">After you complete a haircut, mark the booking as "Complete." The customer pays through the app, and funds are deposited directly to your connected Stripe account. No chasing payments.</p>
                    </div>
                  </div>
                </div>

                <div className="bg-gradient-to-r from-gray-50 to-white border border-gray-200 rounded-xl overflow-hidden">
                  <button 
                    onClick={() => toggleFaq('b4')}
                    className="w-full flex items-center justify-center p-4 cursor-pointer hover:bg-gray-50 transition-colors gap-2"
                  >
                    <h4 className="font-medium text-gray-900">How do I manage my schedule?</h4>
                    <ChevronDown className={`w-4 h-4 text-gray-500 transition-transform duration-300 flex-shrink-0 ${openFaq === 'b4' ? 'rotate-180' : ''}`} />
                  </button>
                  <div className={`grid transition-all duration-300 ease-in-out ${openFaq === 'b4' ? 'grid-rows-[1fr]' : 'grid-rows-[0fr]'}`}>
                    <div className="overflow-hidden">
                      <p className="px-4 pb-4 text-gray-600 text-sm text-center">Set your weekly availability in your profile by choosing which days and hours you're open for bookings. You can also block specific dates and times for one-time events. Optionally, connect your Google Calendar to automatically block times when you're busy—your class schedule, study sessions, and personal events are synced so customers can only book when you're truly available.</p>
                    </div>
                  </div>
                </div>

                <div className="bg-gradient-to-r from-gray-50 to-white border border-gray-200 rounded-xl overflow-hidden">
                  <button 
                    onClick={() => toggleFaq('b6')}
                    className="w-full flex items-center justify-center p-4 cursor-pointer hover:bg-gray-50 transition-colors gap-2"
                  >
                    <h4 className="font-medium text-gray-900">Why connect Google Calendar?</h4>
                    <ChevronDown className={`w-4 h-4 text-gray-500 transition-transform duration-300 flex-shrink-0 ${openFaq === 'b6' ? 'rotate-180' : ''}`} />
                  </button>
                  <div className={`grid transition-all duration-300 ease-in-out ${openFaq === 'b6' ? 'grid-rows-[1fr]' : 'grid-rows-[0fr]'}`}>
                    <div className="overflow-hidden">
                      <p className="px-4 pb-4 text-gray-600 text-sm text-center">Connecting your Google Calendar prevents double-bookings. CampusCut reads your calendar's busy times (like classes, exams, or personal events) and automatically blocks those slots so customers can't book during them. We never see the details of your events—just when you're busy. You can disconnect at any time from your barber dashboard.</p>
                    </div>
                  </div>
                </div>

                <div className="bg-gradient-to-r from-gray-50 to-white border border-gray-200 rounded-xl overflow-hidden">
                  <button 
                    onClick={() => toggleFaq('b5')}
                    className="w-full flex items-center justify-center p-4 cursor-pointer hover:bg-gray-50 transition-colors gap-2"
                  >
                    <h4 className="font-medium text-gray-900">Can I decline booking requests?</h4>
                    <ChevronDown className={`w-4 h-4 text-gray-500 transition-transform duration-300 flex-shrink-0 ${openFaq === 'b5' ? 'rotate-180' : ''}`} />
                  </button>
                  <div className={`grid transition-all duration-300 ease-in-out ${openFaq === 'b5' ? 'grid-rows-[1fr]' : 'grid-rows-[0fr]'}`}>
                    <div className="overflow-hidden">
                      <p className="px-4 pb-4 text-gray-600 text-sm text-center">Absolutely. When you receive a booking request, you can accept or decline. You're in full control of which jobs you take on.</p>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          {/* CTA below FAQ */}
          <div className="mt-12 text-center">
            <p className="text-gray-600 mb-4">Still have questions?</p>
            <button 
              onClick={openContactPopup}
              className="inline-flex items-center gap-2 px-6 py-3 bg-primary-400 hover:bg-primary-500 text-white font-semibold rounded-lg transition-colors"
            >
              <Mail className="w-5 h-5" />
              Contact Support
            </button>
          </div>
        </div>
      </div>

      {/* Final CTA */}
      <div className="py-20 px-4 bg-gradient-to-br from-primary-400 to-primary-500 shadow-[0_-4px_20px_-4px_rgba(0,0,0,0.15)]">
        <div className="max-w-4xl mx-auto text-center">
          <h2 className="text-4xl md:text-5xl font-bold text-white mb-4">
            Want to be a CampusCut Barber?
          </h2>
          <div className="flex justify-center">
            <button 
              onClick={() => setShowBarberApplication(true)}
              className="px-6 py-4 rounded-lg bg-white border-2 border-primary-500 hover:bg-primary-50 transition-colors shadow-lg hover:shadow-xl active:scale-95"
            >
              <span className="text-lg font-semibold text-primary-600">Become a Barber</span>
            </button>
          </div>
        </div>
      </div>

      {/* Barber Application Modal (Guest Mode) */}
      <BarberApplicationModal
        isOpen={showBarberApplication}
        onClose={() => setShowBarberApplication(false)}
        guestMode={true}
      />

      {/* Contact Support Popup */}
      {showContactPopup && (
        <div 
          className={`fixed inset-0 min-h-[100dvh] bg-black/50 flex items-center justify-center z-50 p-4 transition-opacity duration-200 ${contactVisible ? 'opacity-100' : 'opacity-0'}`}
          onClick={closeContactPopup}
        >
          <div 
            className={`bg-white rounded-3xl p-8 max-w-lg w-full max-h-[85dvh] sm:max-h-[90vh] overflow-y-auto transition-all duration-200 ${contactVisible ? 'opacity-100 scale-100' : 'opacity-0 scale-95'}`}
            onClick={(e) => e.stopPropagation()}
          >
            <div className="relative mb-6">
              <h2 className="text-2xl font-bold text-gray-900 text-center">Contact Support</h2>
              <button
                onClick={closeContactPopup}
                className="absolute top-0 right-0 p-2 hover:bg-gray-100 rounded-full transition-colors"
              >
                <X className="w-5 h-5 text-gray-500" />
              </button>
            </div>

            {contactSubmitted ? (
              <div className="text-center py-8">
                <div className="w-16 h-16 bg-green-100 rounded-full flex items-center justify-center mx-auto mb-4">
                  <CheckCircle className="w-8 h-8 text-green-600" />
                </div>
                <h3 className="text-xl font-bold text-gray-900 mb-2">Message Sent!</h3>
                <p className="text-gray-600 mb-6">We'll get back to you as soon as possible.</p>
                <button
                  onClick={closeContactPopup}
                  className="px-6 py-2 bg-primary-400 hover:bg-primary-500 text-white font-semibold rounded-lg transition-colors"
                >
                  Close
                </button>
              </div>
            ) : (
              <form
                onSubmit={(e) => {
                  e.preventDefault();
                  // Open mailto with pre-filled content
                  const subject = encodeURIComponent(`CampusCut Support Request from ${contactForm.name}`);
                  const body = encodeURIComponent(`Name: ${contactForm.name}\nEmail: ${contactForm.email}\n\nMessage:\n${contactForm.message}`);
                  window.location.href = `mailto:campuscuthelp@gmail.com?subject=${subject}&body=${body}`;
                  setContactSubmitted(true);
                }}
                className="space-y-4"
              >
                <div>
                  <label htmlFor="contact-name" className="block text-sm font-medium text-gray-700 mb-1">
                    Your Name
                  </label>
                  <input
                    type="text"
                    id="contact-name"
                    required
                    value={contactForm.name}
                    onChange={(e) => setContactForm({ ...contactForm, name: e.target.value })}
                    className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-primary-400 outline-none transition-colors"
                    placeholder="John Doe"
                  />
                </div>

                <div>
                  <label htmlFor="contact-email" className="block text-sm font-medium text-gray-700 mb-1">
                    Your Email
                  </label>
                  <input
                    type="email"
                    id="contact-email"
                    required
                    value={contactForm.email}
                    onChange={(e) => setContactForm({ ...contactForm, email: e.target.value })}
                    className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-primary-400 outline-none transition-colors"
                    placeholder="john@university.edu"
                  />
                </div>

                <div>
                  <label htmlFor="contact-message" className="block text-sm font-medium text-gray-700 mb-1">
                    Message
                  </label>
                  <textarea
                    id="contact-message"
                    required
                    rows={4}
                    value={contactForm.message}
                    onChange={(e) => setContactForm({ ...contactForm, message: e.target.value })}
                    className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-400 focus:border-primary-400 outline-none transition-colors resize-none"
                    placeholder="How can we help you?"
                  />
                </div>

                <button
                  type="submit"
                  className="w-full px-6 py-3 bg-primary-400 hover:bg-primary-500 text-white font-semibold rounded-lg transition-colors flex items-center justify-center gap-2"
                >
                  <Mail className="w-5 h-5" />
                  Send Message
                </button>

                <p className="text-xs text-gray-500 text-center">
                  This will open your email client with the message pre-filled
                </p>
              </form>
            )}
          </div>
        </div>
      )}

      {/* Campus Manager Application Info Popup */}
      {showCampusManagerInfo && (
        <div 
          className={`fixed inset-0 min-h-[100dvh] bg-black/50 flex items-center justify-center z-50 p-4 transition-opacity duration-200 ${campusManagerInfoVisible ? 'opacity-100' : 'opacity-0'}`}
          onClick={closeCampusManagerInfo}
        >
          <div 
            className={`bg-white rounded-3xl p-8 max-w-lg w-full max-h-[85dvh] sm:max-h-[90vh] overflow-y-auto transition-all duration-200 ${campusManagerInfoVisible ? 'opacity-100 scale-100' : 'opacity-0 scale-95'}`}
            onClick={(e) => e.stopPropagation()}
          >
            <div className="relative mb-6">
              <h2 className="text-2xl font-bold text-gray-900 text-center">Become a Campus Manager</h2>
              <button
                onClick={closeCampusManagerInfo}
                className="absolute top-0 right-0 p-2 hover:bg-gray-100 rounded-full transition-colors"
              >
                <X className="w-5 h-5 text-gray-500" />
              </button>
            </div>

            <div className="space-y-6">
              <div className="bg-gray-50 rounded-xl p-6">
                <h3 className="font-semibold text-gray-900 mb-3">How to Apply</h3>
                <p className="text-gray-600 text-sm mb-4">
                  To apply for the Campus Manager position, send an email to:
                </p>
                <div className="bg-white border border-gray-200 rounded-lg p-2 sm:p-4 flex items-center justify-between gap-2 sm:gap-3">
                  <p className="font-mono text-primary-600 font-medium text-xs sm:text-lg select-all flex-1 text-center">
                    campuscuthelp@gmail.com
                  </p>
                  <button
                    onClick={copyEmailToClipboard}
                    className={`p-2 rounded-lg transition-all ${emailCopied ? 'bg-green-100 text-green-600' : 'hover:bg-gray-100 text-gray-500 hover:text-gray-700'}`}
                    title={emailCopied ? 'Copied!' : 'Copy email'}
                  >
                    {emailCopied ? <Check className="w-5 h-5" /> : <Copy className="w-5 h-5" />}
                  </button>
                </div>
                <p className="text-gray-500 text-sm mt-4">
                  Please include your name, university, and a brief explanation of why you'd be a great Campus Manager.
                </p>
              </div>

              <button
                onClick={closeCampusManagerInfo}
                className="w-full px-6 py-3 bg-primary-500 hover:bg-primary-600 text-white font-semibold rounded-lg transition-colors"
              >
                Got it
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Comprehensive Footer - Inspired by Cluely */}
      <footer className="bg-gray-900 text-white py-12">
        <div className="max-w-7xl mx-auto px-4">
          <div className="grid grid-cols-2 md:grid-cols-3 gap-8 mb-8 justify-items-center text-center">
            {/* Resources */}
            <div>
              <h4 className="font-bold text-white mb-4">Resources</h4>
              <ul className="space-y-2">
                <li>
                  <button onClick={() => scrollToSection('how-it-works')} className="text-gray-400 hover:text-white transition-colors">
                    See Our Work
                  </button>
                </li>
                <li>
                  <button onClick={() => scrollToSection('campus-manager')} className="text-gray-400 hover:text-white transition-colors">
                    Campus Manager
                  </button>
                </li>
                <li>
                  <button onClick={() => scrollToSection('pricing')} className="text-gray-400 hover:text-white transition-colors">
                    Pricing Explained
                  </button>
                </li>
              </ul>
            </div>

            {/* Support */}
            <div>
              <h4 className="font-bold text-white mb-4">Support</h4>
              <ul className="space-y-2">
                <li>
                  <button onClick={openContactPopup} className="text-gray-400 hover:text-white transition-colors inline-flex items-center gap-1 justify-center">
                    Contact Us <Mail className="w-3 h-3" />
                  </button>
                </li>
                <li>
                  <button onClick={() => scrollToSection('faq')} className="text-gray-400 hover:text-white transition-colors">
                    FAQ
                  </button>
                </li>
              </ul>
            </div>

            {/* Legal */}
            <div>
              <h4 className="font-bold text-white mb-4">Legal</h4>
              <ul className="space-y-2">
                <li>
                  <a href="https://campuscut.com/privacy" className="text-gray-400 hover:text-white transition-colors">
                    Privacy Policy
                  </a>
                </li>
                <li>
                  <a href="https://campuscut.com/terms" className="text-gray-400 hover:text-white transition-colors">
                    Terms of Service
                  </a>
                </li>
                <li>
                  <a href="https://campuscut.com/gdpr" className="text-gray-400 hover:text-white transition-colors">
                    GDPR
                  </a>
                </li>
              </ul>
            </div>
          </div>

          {/* Bottom Bar */}
          <div className="border-t border-gray-800 pt-8">
            <div className="flex flex-col items-center justify-center gap-4">
              {/* Logo and Copyright */}
              <div className="flex items-center gap-3">
                <img src={FooterChairLogo} alt="CampusCut" className="h-8 w-auto" />
                <div>
                  <p className="text-gray-400 text-sm">
                    © 2026 CampusCut. All rights reserved.
                  </p>
                </div>
              </div>

              {/* Quick Legal Links - Prominent placement for Google verification */}
              <div className="flex items-center gap-4 text-sm">
                <a href="https://campuscut.com/privacy" className="text-gray-400 hover:text-white transition-colors">
                  Privacy Policy
                </a>
                <span className="text-gray-600">|</span>
                <a href="https://campuscut.com/terms" className="text-gray-400 hover:text-white transition-colors">
                  Terms of Service
                </a>
              </div>

              {/* Social Links */}
              <div className="flex items-center gap-4">
                <a href="https://www.instagram.com/campuscut.c0m/" target="_blank" rel="noopener noreferrer" className="text-gray-400 hover:text-white transition-colors">
                  <Instagram className="w-5 h-5" />
                </a>
                <a 
                  href="https://www.youtube.com/@CampusCutCalPoly" 
                  target="_blank" 
                  rel="noopener noreferrer"
                  className="text-gray-400 hover:text-white transition-colors"
                  aria-label="YouTube"
                >
                  <Youtube className="w-5 h-5" />
                </a>
              </div>
            </div>

          </div>
        </div>
      </footer>
    </PullToRefresh>
  );
}
