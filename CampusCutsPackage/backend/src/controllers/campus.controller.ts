import { Response, NextFunction } from 'express';
import { pool } from '../database/connection';
import { ApiError } from '../middleware/errorHandler';
import { AuthRequest } from '../middleware/auth';

export const getAllCampuses = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { search } = req.query;
    
    let query = `
      SELECT id, name, slug, city, state, domain, latitude, longitude 
      FROM campuses 
      WHERE "isActive" = TRUE
    `;
    const params: string[] = [];
    
    // Optional search filter
    if (search && typeof search === 'string' && search.length >= 1) {
      params.push(`%${search.toLowerCase()}%`);
      query += ` AND (LOWER(name) LIKE $1 OR LOWER(city) LIKE $1 OR LOWER(slug) LIKE $1)`;
    }
    
    query += ` ORDER BY name`;
    
    const result = await pool.query(query, params);

    res.json({
      success: true,
      data: result.rows,
      count: result.rows.length,
    });
  } catch (error) {
    next(error);
  }
};

export const getCampusById = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;

    const result = await pool.query(
      'SELECT * FROM campuses WHERE id = $1',
      [id]
    );

    if (result.rows.length === 0) {
      throw new ApiError(404, 'Campus not found');
    }

    res.json({
      success: true,
      data: result.rows[0],
    });
  } catch (error) {
    next(error);
  }
};

export const getCampusBarbers = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;
    const { sortBy } = req.query;

    let orderClause = 'b.average_rating DESC';

    if (sortBy === 'price') {
      orderClause = 'b.pricing ASC';
    } else if (sortBy === 'bookings') {
      orderClause = 'b.total_bookings DESC';
    }

    const result = await pool.query(
      `SELECT b.*, u.first_name, u.last_name,
        COALESCE(json_agg(
          json_build_object('url', pi.image_url)
          ORDER BY pi.order_index
        ) FILTER (WHERE pi.id IS NOT NULL), '[]') as portfolio_preview
      FROM barbers b
      JOIN users u ON b.user_id = u.id
      LEFT JOIN portfolio_images pi ON b.id = pi.barber_id
      WHERE u.campus_id = $1 AND u.is_active = TRUE
      GROUP BY b.id, u.first_name, u.last_name
      ORDER BY ${orderClause}`,
      [id]
    );

    res.json({
      success: true,
      data: result.rows,
      count: result.rows.length,
    });
  } catch (error) {
    next(error);
  }
};

export const getCampusStats = async (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;

    const stats = await pool.query(
      `SELECT 
        COUNT(DISTINCT b.id) as total_barbers,
        COUNT(DISTINCT bm.client_id) as total_clients,
        COUNT(bm.blockchain_booking_id) as total_bookings,
        AVG(b.average_rating) as avg_rating
      FROM barbers b
      JOIN users u ON b.user_id = u.id
      LEFT JOIN booking_metadata bm ON b.id = bm.barber_id
      WHERE u.campus_id = $1`,
      [id]
    );

    res.json({
      success: true,
      data: stats.rows[0],
    });
  } catch (error) {
    next(error);
  }
};

