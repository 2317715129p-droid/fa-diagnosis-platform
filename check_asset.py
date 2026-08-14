import sqlite3
conn = sqlite3.connect('fa_data.db')
cursor = conn.execute("SELECT asset_id, server_model, status FROM assets WHERE asset_id='TestNode-01'")
row = cursor.fetchone()
conn.close()

if row:
    print(f"Asset found: ID={row[0]}, Model={row[1]}, Status={row[2]}")
else:
    print("Not found - asset not created")