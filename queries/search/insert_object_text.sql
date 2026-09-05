INSERT INTO object_text(rowid, title, people, body, attachment, place, org, note,
                        "from", "to", cc, bcc, email, organizer, attendee)
VALUES(:rowid, :title, :people, :body, :attachment, :place, :org, :note,
       :from, :to, :cc, :bcc, :email, :organizer, :attendee);
