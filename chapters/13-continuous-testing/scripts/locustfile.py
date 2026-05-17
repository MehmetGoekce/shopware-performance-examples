# locustfile.py — Last-Test für Shopware 6 (Locust, Open Source)
# Kapitel 13: Continuous Testing
#
# Ausführen:  locust -f locustfile.py --host=https://staging.example.com
#             (Web-UI auf http://localhost:8089)
# Headless:   locust -f locustfile.py --host=https://staging.example.com \
#                    --headless -u 50 -r 10 -t 5m
#
# WICHTIG: niemals gegen Production — Staging mit produktionsnaher
# Datenmenge und identischer Cache-Konfiguration.
#
# @see https://github.com/MehmetGoekce/shopware-performance-examples

from locust import HttpUser, task, between


class ShopUser(HttpUser):
    wait_time = between(1, 3)

    @task(3)
    def listing(self):
        # Gecachter Pfad
        self.client.get("/")

    @task(1)
    def search(self):
        # Uncachebarer Pfad — DB/PHP-Last sichtbar
        self.client.get("/search?search=shirt")
