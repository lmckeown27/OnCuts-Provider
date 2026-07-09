/**
 * QR Code Generation Script
 * 
 * Generates a CampusCut QR code with the official logo.
 * 
 * Usage:
 *   npx ts-node src/scripts/generate-qr.ts [url] [output-path]
 * 
 * Examples:
 *   npx ts-node src/scripts/generate-qr.ts
 *   npx ts-node src/scripts/generate-qr.ts https://campuscut.com
 *   npx ts-node src/scripts/generate-qr.ts https://campuscut.com ./output/my-qr.png
 */

import * as path from 'path';
import { generateQrWithLogo, CAMPUSCUT_LOGO_PATH } from '../utils/qr';

async function main() {
  const args = process.argv.slice(2);
  
  const url = args[0] || 'https://campuscut.com';
  const outputPath = args[1] || path.resolve(__dirname, '../../output/campuscut-qr.png');
  
  console.log('🔲 Generating QR code...');
  console.log(`   URL: ${url}`);
  console.log(`   Logo: ${CAMPUSCUT_LOGO_PATH}`);
  console.log(`   Output: ${outputPath}`);
  
  try {
    const savedPath = await generateQrWithLogo({
      url,
      logoPath: CAMPUSCUT_LOGO_PATH,
      outputPath,
    });
    
    console.log(`\n✅ QR code generated successfully!`);
    console.log(`   Saved to: ${savedPath}`);
  } catch (error) {
    console.error('\n❌ Failed to generate QR code:', error);
    process.exit(1);
  }
}

main();

