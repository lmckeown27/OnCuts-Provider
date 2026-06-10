/**
 * Mobile Photo Upload Component
 * 
 * Provides a mobile-friendly interface for uploading profile photos.
 * Uses the native file picker which on mobile devices shows options like:
 * - Photo Library
 * - Take Photo
 * - Choose File
 * 
 * Images are processed client-side using Canvas API to:
 * - Convert HEIC/HEIF to JPEG (iOS compatibility)
 * - Fix orientation issues
 * - Resize to reasonable dimensions
 * - Ensure proper MIME type for upload
 */

import { useRef, useState } from 'react';
import { ImageIcon, Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';

interface MobilePhotoUploadProps {
  currentPhotoUrl?: string;
  onPhotoSelected: (file: File) => Promise<void>;
  isUploading?: boolean;
  maxSizeMB?: number;
  className?: string;
  /** Shape of the profile picture preview - 'circle' for consumers, 'square' for barbers */
  shape?: 'circle' | 'square';
}

/**
 * Convert a data URL to a File object
 */
const dataURLtoFile = (dataURL: string, filename: string): File => {
  const arr = dataURL.split(',');
  const mime = arr[0].match(/:(.*?);/)?.[1] || 'image/jpeg';
  const bstr = atob(arr[1]);
  let n = bstr.length;
  const u8arr = new Uint8Array(n);
  while (n--) {
    u8arr[n] = bstr.charCodeAt(n);
  }
  return new File([u8arr], filename, { type: mime });
};

/**
 * Process image through Canvas API to normalize format and fix orientation
 * This converts HEIC/HEIF to JPEG and ensures proper MIME type
 */
const processImageWithCanvas = (file: File): Promise<File> => {
  return new Promise((resolve, reject) => {
    console.log('[MobilePhotoUpload] Processing image with Canvas:', { name: file.name, size: file.size, type: file.type });
    
    const reader = new FileReader();
    
    reader.onload = (e) => {
      const img = new Image();
      
      img.onload = () => {
        try {
          console.log('[MobilePhotoUpload] Image loaded:', { width: img.width, height: img.height });
          
          const canvas = document.createElement('canvas');
          const ctx = canvas.getContext('2d');
          
          if (!ctx) {
            console.warn('[MobilePhotoUpload] Canvas context not available, using original file');
            resolve(file);
            return;
          }

          // Calculate dimensions - max 800px for profile photos
          const maxDimension = 800;
          let targetWidth = img.width;
          let targetHeight = img.height;

          if (img.width > maxDimension || img.height > maxDimension) {
            if (img.width > img.height) {
              targetWidth = maxDimension;
              targetHeight = Math.round((img.height / img.width) * maxDimension);
            } else {
              targetHeight = maxDimension;
              targetWidth = Math.round((img.width / img.height) * maxDimension);
            }
          }

          console.log('[MobilePhotoUpload] Resizing to:', { targetWidth, targetHeight });

          // Set canvas dimensions
          canvas.width = targetWidth;
          canvas.height = targetHeight;

          // Draw image (this also fixes orientation automatically in modern browsers)
          ctx.drawImage(img, 0, 0, targetWidth, targetHeight);

          // Convert to JPEG data URL with 85% quality
          const jpegDataUrl = canvas.toDataURL('image/jpeg', 0.85);
          
          // Convert data URL back to File
          const processedFile = dataURLtoFile(jpegDataUrl, `profile-${Date.now()}.jpg`);
          
          console.log('[MobilePhotoUpload] Image processed successfully:', { 
            originalSize: file.size, 
            processedSize: processedFile.size,
            processedType: processedFile.type
          });
          
          resolve(processedFile);
        } catch (error) {
          console.error('[MobilePhotoUpload] Canvas processing failed:', error);
          // Fallback to original file
          resolve(file);
        }
      };
      
      img.onerror = (error) => {
        console.error('[MobilePhotoUpload] Image load failed:', error);
        reject(new Error('Failed to load image'));
      };
      
      img.src = e.target?.result as string;
    };
    
    reader.onerror = (error) => {
      console.error('[MobilePhotoUpload] FileReader failed:', error);
      reject(new Error('Failed to read file'));
    };
    
    reader.readAsDataURL(file);
  });
};

export default function MobilePhotoUpload({
  currentPhotoUrl,
  onPhotoSelected,
  isUploading = false,
  maxSizeMB = 10, // Increased since we process before upload
  className = '',
  shape = 'circle', // Default to circle, use 'square' for barbers
}: MobilePhotoUploadProps) {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [isProcessing, setIsProcessing] = useState(false);

  const validateAndUpload = async (file: File | undefined) => {
    console.log('[MobilePhotoUpload] validateAndUpload called', { file: file ? { name: file.name, size: file.size, type: file.type } : null });
    
    if (!file) {
      console.warn('[MobilePhotoUpload] No file provided');
      return;
    }

    // Get file extension for fallback validation
    const fileName = file.name.toLowerCase();
    const extension = fileName.split('.').pop() || '';
    const allowedExtensions = ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'gif', 'bmp'];
    
    // Validate file type - check MIME type OR extension (iOS Photo Library may have empty MIME type)
    const isImageMime = file.type.startsWith('image/') || file.type === '' || file.type === 'application/octet-stream';
    const hasValidExtension = allowedExtensions.includes(extension);
    
    console.log('[MobilePhotoUpload] File validation:', { fileName, extension, isImageMime, hasValidExtension, mimeType: file.type });
    
    if (!isImageMime && !hasValidExtension) {
      console.error('[MobilePhotoUpload] Invalid file type rejected');
      toast.error('Please select an image file');
      return;
    }

    // Validate file size (before processing)
    if (file.size > maxSizeMB * 1024 * 1024) {
      console.error('[MobilePhotoUpload] File too large:', file.size);
      toast.error(`Image must be less than ${maxSizeMB}MB`);
      return;
    }

    setIsProcessing(true);
    
    try {
      // Process image through Canvas to normalize format
      console.log('[MobilePhotoUpload] Starting Canvas processing...');
      const processedFile = await processImageWithCanvas(file);
      console.log('[MobilePhotoUpload] Canvas processing complete, calling onPhotoSelected');
      
      await onPhotoSelected(processedFile);
      console.log('[MobilePhotoUpload] onPhotoSelected completed successfully');
    } catch (error) {
      console.error('[MobilePhotoUpload] Processing/upload failed:', error);
      toast.error('Failed to process image. Please try again.');
    } finally {
      setIsProcessing(false);
    }
  };

  const handleButtonClick = () => {
    fileInputRef.current?.click();
  };

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    console.log('[MobilePhotoUpload] handleFileChange triggered');
    console.log('[MobilePhotoUpload] Input files:', e.target.files);
    const file = e.target.files?.[0];
    if (file) {
      console.log('[MobilePhotoUpload] File selected:', { name: file.name, size: file.size, type: file.type });
    } else {
      console.log('[MobilePhotoUpload] No file in input');
    }
    validateAndUpload(file);
    // Reset input so the same file can be selected again
    e.target.value = '';
  };
  
  const showLoading = isUploading || isProcessing;

  // Determine container classes based on shape
  const shapeClasses = shape === 'square' 
    ? 'w-48 aspect-square rounded-lg' // Square with rounded corners for barbers
    : 'w-32 h-32 rounded-full'; // Circle for consumers

  return (
    <div className={className}>
      {/* Current Profile Picture Display */}
      <div className="flex flex-col items-center">
        <div className={`${shapeClasses} overflow-hidden bg-gray-200 mb-4`}>
          {currentPhotoUrl ? (
            <img
              src={currentPhotoUrl}
              alt="Profile"
              className="w-full h-full object-cover"
            />
          ) : (
            <div className="w-full h-full flex items-center justify-center">
              <ImageIcon className="w-12 h-12 text-gray-400" />
            </div>
          )}
        </div>

        {/* Change Profile Picture Button */}
        <button
          onClick={handleButtonClick}
          disabled={showLoading}
          className="px-4 py-2 bg-primary-50 text-primary-600 rounded-lg font-medium hover:bg-primary-100 active:scale-95 transition-all disabled:opacity-50"
        >
          {showLoading ? (
            <span className="flex items-center gap-2">
              <Loader2 className="w-4 h-4 animate-spin" />
              {isProcessing ? 'Processing...' : 'Uploading...'}
            </span>
          ) : (
            'Change Profile Picture'
          )}
        </button>
        <p className="text-xs text-gray-500 mt-2">Supports JPG, PNG, HEIC</p>
      </div>

      {/* Hidden File Input - triggers native picker with Photo Library, Take Photo, Choose File options */}
      {/* Note: Do NOT use capture attribute - it forces camera only. Without it, iOS shows all 3 options */}
      <input
        ref={fileInputRef}
        type="file"
        accept="image/*"
        onChange={handleFileChange}
        className="hidden"
      />
    </div>
  );
}

