-- Sample data (INSERT). Dates are relative to today so the demo never goes stale.
INSERT INTO users(full_name, email, phone, role) VALUES
 ('Admin Manager', 'admin@turfzone.in', '9000000001', 'admin'),
 ('Rohan Mehta',   'rohan@mail.com',    '9000000002', 'customer'),
 ('Priya Sharma',  'priya@mail.com',    '9000000003', 'customer'),
 ('Arjun Nair',    'arjun@mail.com',    '9000000004', 'customer'),
 ('Sneha Kulkarni','sneha@mail.com',    '9000000005', 'customer'),
 ('Karan Patel',   'karan@mail.com',    '9000000006', 'customer');

INSERT INTO sports(sport_name) VALUES ('Football'),('Cricket'),('Badminton'),('Pickleball'),('Basketball'),('Tennis');

INSERT INTO turfs(name, city, area, price_per_hour, capacity, description) VALUES
 ('Green Arena',     'Mumbai',      'Andheri West', 1500, 14, 'FIFA-grade artificial grass with floodlights and changing rooms.'),
 ('Kick Off Turf',   'Mumbai',      'Bandra',       1200, 12, 'Compact 5-a-side turf, perfect for evening matches.'),
 ('Smash Court',     'Mumbai',      'Powai',         800,  8, 'Indoor wooden courts with pro lighting.'),
 ('Victory Grounds', 'Pune',        'Baner',        1000, 22, 'Large ground for cricket and football with spectator seating.'),
 ('Royal Turf',      'Pune',        'Kothrud',      1800, 22, 'Premium turf with cafe, parking and first-aid.'),
 ('Urban Play Box',  'Navi Mumbai', 'Vashi',         900, 10, 'Brand new box turf - open for bookings.');

INSERT INTO turf_sports(turf_id, sport_id) VALUES
 (1,1),(1,2),(2,1),(2,4),(3,3),(3,4),(4,1),(4,2),(5,1),(5,2),(5,5),(6,4),(6,5);

INSERT INTO bookings(user_id, turf_id, sport_id, booking_date, start_time, end_time, total_amount, status) VALUES
 (2,1,1, CURRENT_DATE-20, '18:00','20:00', 3000,'COMPLETED'),
 (3,1,2, CURRENT_DATE-15, '19:00','20:00', 1500,'COMPLETED'),
 (2,2,1, CURRENT_DATE-12, '07:00','09:00', 2400,'COMPLETED'),
 (4,3,3, CURRENT_DATE-10, '20:00','21:00',  800,'COMPLETED'),
 (5,4,1, CURRENT_DATE-8,  '17:00','19:00', 2000,'COMPLETED'),
 (3,5,2, CURRENT_DATE-6,  '21:00','22:00', 1800,'CANCELLED'),
 (2,5,1, CURRENT_DATE-5,  '18:00','20:00', 3600,'COMPLETED'),
 (4,1,1, CURRENT_DATE-3,  '06:00','07:00', 1500,'COMPLETED'),
 (5,2,4, CURRENT_DATE+2,  '18:00','20:00', 2400,'CONFIRMED'),
 (3,1,1, CURRENT_DATE+3,  '19:00','21:00', 3000,'CONFIRMED'),
 (2,4,2, CURRENT_DATE+4,  '16:00','17:00', 1000,'CONFIRMED'),
 (6,3,4, CURRENT_DATE-2,  '17:00','18:00',  800,'COMPLETED'),
 (4,6,4, CURRENT_DATE-1,  '19:00','20:00',  900,'COMPLETED'),
 (6,1,2, CURRENT_DATE+1,  '10:00','12:00', 3000,'CONFIRMED'),
 (3,6,5, CURRENT_DATE+5,  '18:00','19:00',  900,'CONFIRMED');

-- INSERT ... SELECT : one payment row per booking
INSERT INTO payments(booking_id, amount, method, status)
SELECT booking_id, total_amount, (ARRAY['UPI','CARD','CASH'])[1 + booking_id % 3],
       CASE WHEN status = 'CANCELLED' THEN 'REFUNDED' ELSE 'PAID' END
FROM bookings;

INSERT INTO reviews(user_id, turf_id, rating, comment) VALUES
 (2,1,5,'Best turf in Andheri, lights are superb!'),
 (2,2,4,'Good for small groups.'),
 (4,3,3,'Courts are fine, AC could be better.'),
 (5,4,5,'Huge ground, loved the seating.'),
 (2,5,4,'Premium experience, a bit pricey.'),
 (4,1,5,'Early morning game was perfect.');
