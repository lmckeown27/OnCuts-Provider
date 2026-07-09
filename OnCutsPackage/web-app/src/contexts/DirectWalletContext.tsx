// @ts-nocheck
/**
 * Direct Wallet Context
 * 
 * DISABLED - Wallet/blockchain functionality not currently in use.
 * Platform uses Stripe for payments.
 * 
 * This file is kept for future blockchain integration.
 * All wallet detection and connection code is commented out
 * to prevent browser wallet extension detection issues.
 */

import React, { createContext, useContext, ReactNode } from 'react';

interface DirectWalletContextType {
  connected: boolean;
  address: string;
  petraInstalled: boolean;
  wallet: any;
  connectWallet: () => Promise<void>;
  disconnectWallet: () => Promise<void>;
  getAccount: () => { address: string } | null;
  signAndSubmitTransaction: (payload: any) => Promise<any>;
}

const DirectWalletContext = createContext<DirectWalletContextType | undefined>(undefined);

interface DirectWalletProviderProps {
  children: ReactNode;
}

// Disabled provider - returns mock values, no wallet detection
export function DirectWalletProvider({ children }: DirectWalletProviderProps) {
  const value: DirectWalletContextType = {
    connected: false,
    address: '',
    petraInstalled: false,
    wallet: null,
    connectWallet: async () => {
      console.log('⚠️ Wallet functionality is disabled');
    },
    disconnectWallet: async () => {
      console.log('⚠️ Wallet functionality is disabled');
    },
    getAccount: () => null,
    signAndSubmitTransaction: async () => {
      throw new Error('Wallet functionality is disabled');
    },
  };

  return (
    <DirectWalletContext.Provider value={value}>
      {children}
    </DirectWalletContext.Provider>
  );
}

export function useDirectWallet() {
  const context = useContext(DirectWalletContext);
  
  if (context === undefined) {
    // Return a safe default instead of throwing
    return {
      connected: false,
      address: '',
      petraInstalled: false,
      wallet: null,
      connectWallet: async () => {},
      disconnectWallet: async () => {},
      getAccount: () => null,
      signAndSubmitTransaction: async () => { throw new Error('Wallet disabled'); },
    };
  }
  
  return context;
}
