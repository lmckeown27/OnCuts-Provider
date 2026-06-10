/**
 * Image Optimization Script
 * Converts PNG images to WebP format for smaller file sizes
 * 
 * Run with: node scripts/optimize-images.mjs
 */

import sharp from 'sharp';
import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const LOGOS_DIR = path.join(__dirname, '../src/assets/logos');

async function optimizeImages() {
  console.log('🖼️  Starting image optimization...\n');
  
  const files = await fs.readdir(LOGOS_DIR);
  const pngFiles = files.filter(f => f.endsWith('.png'));
  
  let totalOriginalSize = 0;
  let totalOptimizedSize = 0;
  
  for (const file of pngFiles) {
    const inputPath = path.join(LOGOS_DIR, file);
    const outputPath = path.join(LOGOS_DIR, file.replace('.png', '.webp'));
    
    const originalStats = await fs.stat(inputPath);
    totalOriginalSize += originalStats.size;
    
    // Convert to WebP with quality optimization
    await sharp(inputPath)
      .webp({ 
        quality: 85,  // Good quality with compression
        effort: 6,    // Higher effort = better compression
      })
      .toFile(outputPath);
    
    const optimizedStats = await fs.stat(outputPath);
    totalOptimizedSize += optimizedStats.size;
    
    const savings = ((1 - optimizedStats.size / originalStats.size) * 100).toFixed(1);
    console.log(`✅ ${file} → ${file.replace('.png', '.webp')}`);
    console.log(`   ${(originalStats.size / 1024).toFixed(0)} KB → ${(optimizedStats.size / 1024).toFixed(0)} KB (${savings}% smaller)\n`);
  }
  
  const totalSavings = ((1 - totalOptimizedSize / totalOriginalSize) * 100).toFixed(1);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`📊 Total: ${(totalOriginalSize / 1024 / 1024).toFixed(2)} MB → ${(totalOptimizedSize / 1024 / 1024).toFixed(2)} MB`);
  console.log(`💾 Saved: ${totalSavings}% (${((totalOriginalSize - totalOptimizedSize) / 1024 / 1024).toFixed(2)} MB)`);
  console.log('\n✨ Done! Now update your imports to use .webp files.');
}

optimizeImages().catch(console.error);

